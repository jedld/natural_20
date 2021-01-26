# typed: false
module Natural20
  class Battle
    attr_accessor :combat_order, :round, :current_party
    attr_reader :map, :entities, :session, :battle_log, :started, :in_combat

    # Create an instance of a battle
    # @param session [Natural20::Session]
    # @param map [Natural20::BattleMap]
    # @param standard_controller [AiController::Standard]
    def initialize(session, map, standard_controller = nil)
      @session = session
      @entities = {}
      @groups = {}
      @battle_field_events = {}
      @battle_log = []
      @combat_order = []
      @late_comers = []
      @current_turn_index = 0
      @round = 0
      @map = map
      @in_combat = false
      @standard_controller = standard_controller

      @opposing_groups = {
        a: [:b],
        b: [:a]
      }

      standard_controller&.register_battle_listeners(self)
    end

    # Registers a player party
    # @param party [Array<Natural20::Entity>] Initial Player character party
    # @param controller [Natural20::Controller] An object to be used as callback controller
    def register_players(party, controller)
      return if party.blank?

      party.each_with_index do |pc, index|
        add(pc, :a, position: "spawn_point_#{index + 1}", controller: controller)
      end
      @current_party = party
      @combat_order = party
    end

    # Updates opposing player groups to determine who is the enemy of who
    # @param opposing_groups [Hash{Symbol=>Array<Symbol>}]
    def update_group_dynamics(opposing_groups)
      @opposing_groups = opposing_groups
    end

    def add_battlefield_event_listener(event, object, handler)
      @battle_field_events[event.to_sym] ||= []
      @battle_field_events[event.to_sym] << [object, handler]
    end

    def two_weapon_attack?(entity)
      !!entity_state_for(entity)[:two_weapon]
    end

    def first_hand_weapon(entity)
      entity_state_for(entity)[:two_weapon]
    end

    # Adds an entity to the battle
    # @param entity [Natural20::Entity] The entity to add to the battle
    # @param group [Symbol] A symbol denoting which group this entity belongs to
    # @param controller [AiController::Standard] Ai controller to use
    # @param position [Array, Symbol] Starting location in the map can be a position or a spawn point
    # @param token [String, Symbol] The token to use
    def add(entity, group, controller: nil, position: nil, token: nil)
      return if @entities[entity]

      raise 'entity cannot be nil' if entity.nil?

      state = {
        group: group,
        action: 0,
        bonus_action: 0,
        reaction: 0,
        movement: 0,
        stealth: 0,
        statuses: Set.new,
        free_object_interaction: 0,
        target_effect: {},
        two_weapon: nil,
        controller: controller || @standard_controller
      }

      @entities[entity] = state

      battle_defaults = entity.try(:battle_defaults)
      if battle_defaults
        battle_defaults[:statuses].each { |s| state[:statuses].add(s.to_sym) }
        unless state[:stealth].blank?
          state[:stealth] =
            DieRoll.roll(battle_defaults[:stealth], description: t('dice_roll.stealth'), entity: entity,
                                                    battle: self).result
        end
      end

      @groups[group] ||= Set.new
      @groups[group].add(entity)

      # battle already ongoing...
      if started
        @late_comers << entity
        @entities[entity][:initiative] = entity.initiative!(self)
      end

      return if position.nil?
      return if @map.nil?

      position.is_a?(Array) ? @map.place(*position, entity, token) : @map.place_at_spawn_point(position, entity, token)
    end

    def in_battle?(entity)
      @entities.key?(entity)
    end

    def move_for(entity)
      @entities[entity][:controller].move_for(entity, self)
    end

    def controller_for(entity)
      return nil unless @entities.key? entity

      @entities[entity][:controller]
    end

    def roll_for(entity, die_type, number_of_times, description, advantage: false, disadvantage: false)
      if @entities[entity][:controller]
        rolls = @entities[entity][:controller].try(:roll_for, entity, die_type, number_of_times, description,
                                                   advantage: advantage, disadvantage: disadvantage)
        return rolls if rolls
      end

      if advantage || disadvantage
        number_of_times.times.map { [(1..die_type).to_a.sample, (1..die_type).to_a.sample] }
      else
        number_of_times.times.map { (1..die_type).to_a.sample }
      end
    end

    # @param entity [Natural20::Entity]
    # @return [Hash]
    def entity_state_for(entity)
      @entities[entity]
    end

    def entity_group_for(entity)
      return :none unless @entities[entity]

      @entities[entity][:group]
    end

    def dismiss_help_actions_for(source)
      @entities.each do |_k, entity|
        entity[:target_effect]&.delete(source) if %i[help help_ability_check].include?(entity[:target_effect][source])
      end
    end

    def help_with?(target)
      return @entities[target][:target_effect].values.include?(:help) if @entities[target]

      false
    end

    def dismiss_help_for(target)
      return unless @entities[target]

      @entities[target][:target_effect].delete_if { |_k, v| v == :help }
    end

    def action(source, action_type, opts = {})
      action = source.available_actions(@session).detect { |act| act.action_type == action_type }
      opts[:battle] = self
      return action.resolve(@session, @map, opts) if action

      nil
    end

    def action!(action)
      opts = {
        battle: self
      }
      action.resolve(@session, @map, opts)
    end

    def compute_max_weapon_range(action, range = nil)
      case action.action_type
      when :help
        5
      when :attack
        if action.npc_action
          action.npc_action[:range_max].presence || action.npc_action[:range]
        elsif action.using
          weapon = session.load_weapon(action.using)
          if action.thrown
            weapon.dig(:thrown, :range_max) || weapon.dig(:thrown, :range) || weapon[:range]
          else
            weapon[:range_max].presence || weapon[:range]
          end
        end
      else
        range
      end
    end

    # Generates targets that make sense for a given action
    # @param entity [Natural20::Entity]
    # @param action [Natural20::Action]
    # @option target_types [Array<Symbol>]
    # @return [Natural20::Entity]
    def valid_targets_for(entity, action, target_types: [:enemies], range: nil, active_perception: nil, include_objects: false)
      raise 'not an action' unless action.is_a?(Natural20::Action)

      target_types = target_types&.map(&:to_sym) || [:enemies]
      entity_group = @entities[entity][:group]
      attack_range = compute_max_weapon_range(action, range)

      raise 'attack range cannot be nil' if attack_range.nil?

      targets = @entities.map do |k, prop|
        next if !target_types.include?(:self) && k == entity
        next if !target_types.include?(:allies) && prop[:group] == entity_group && k != entity
        next if !target_types.include?(:enemies) && opposing?(entity, k)
        next if k.dead?
        next if !target_types.include?(:ignore_los) && !can_see?(entity, k, active_perception: active_perception)
        next if @map.distance(k, entity) * @map.feet_per_grid > attack_range

        k
      end.compact

      if include_objects
        targets += @map.interactable_objects.map do |object, _position|
          next if object.dead?
          next if !target_types.include?(:ignore_los) && !can_see?(entity, object, active_perception: active_perception)
          next if @map.distance(object, entity) * @map.feet_per_grid > attack_range

          object
        end.compact
      end

      targets
    end

    # Determines if an entity can see someone in battle
    # @param entity1 [Natural20::Entity] observer
    # @param entity2 [Natural20::Entity] entity being observed
    # @return [Boolean]
    def can_see?(entity1, entity2, active_perception: nil)
      return true if entity1 == entity2
      return false unless @map.can_see?(entity1, entity2)
      return true unless entity2.hiding?(self)

      cover_value = @map.cover_calculation(@map, entity1, entity2)
      if cover_value.positive?
        entity_2_state = entity_state_for(entity2)
        return false if entity_2_state[:stealth] > (active_perception || entity1.passive_perception)
      end

      true
    end

    # Retruns opponents of entity
    # @param entity [Natural20::Entity] target entity
    # @return [Array<Natrual20::Entity>]
    def opponents_of?(entity)
      (@entities.keys + @late_comers).reject(&:dead?).select do |k|
        opposing?(k, entity)
      end
    end

    # Determines if two entities are opponents of each other
    # @param entity1 [Natural20::Entity]
    # @param entity2 [Natural20::Entity]
    # @return [Boolean]
    def opposing?(entity1, entity2)
      source_state1 = entity_state_for(entity1)
      source_state2 = entity_state_for(entity2)
      return false if source_state1.nil? || source_state2.nil?

      source_group1 = source_state1[:group]
      source_group2 = source_state2[:group]

      @opposing_groups[source_group1]&.include?(source_group2)
    end

    # Checks if this entity is controlled by AI or Person
    # @param entity [Natural20::Entity]
    # @return [Boolean]
    def has_controller_for?(entity)
      raise 'unknown entity in battle' unless @entities.key?(entity)

      @entities[entity][:controller] != :manual
    end

    # consume action resource and return if something changed
    def consume!(entity, resource, qty)
      current_qty = entity_state_for(entity)[resource.to_sym]
      new_qty = [0, current_qty - qty].max
      entity_state_for(entity)[resource.to_sym] = new_qty

      current_qty != new_qty
    end

    # @param combat_order [Array] If specified will use this array as the initiative order
    def start(combat_order = nil)
      if combat_order
        @combat_order = combat_order
        return
      end

      # roll for initiative
      @combat_order = @entities.map do |entity, v|
        v[:initiative] = entity.initiative!(self)

        entity
      end

      @started = true
      @current_turn_index = 0
      @combat_order = @combat_order.sort_by { |a| @entities[a][:initiative] || a.name }.reverse
    end

    # @return [Natural20::Entity]
    def current_turn
      @combat_order[@current_turn_index]
    end

    def check_combat
      if !@started && !battle_ends?
        Natural20::EventManager.received_event(source: self, event: :start_of_combat, target: current_turn)
        start
        return true
      end
      false
    end

    def while_active(max_rounds = nil, &block)
      loop do
        Natural20::EventManager.received_event(source: self, event: :start_of_round)

        current_turn.death_saving_throw!(self) if current_turn.unconscious? && !current_turn.stable?

        if current_turn.conscious?
          current_turn.reset_turn!(self)
          block.call(current_turn)
        end

        trigger_event!(:end_of_round, self, target: current_turn)

        if @started && battle_ends?
          Natural20::EventManager.received_event(source: self, event: :end_of_combat)
          @started = false
        end

        @current_turn_index += 1
        next unless @current_turn_index >= @combat_order.length

        @current_turn_index = 0
        @round += 1

        # top of the round
        @combat_order += @late_comers
        @late_comers.clear
        @combat_order = @combat_order.sort_by { |a| @entities[a][:initiative] || a.name }.reverse
        session.increment_game_time!

        Natural20::EventManager.received_event({ source: self, event: :top_of_the_round, round: @round,
                                                 target: current_turn })

        return if !max_rounds.nil? && @round > max_rounds
      end
    end

    # Determines if there is a conscious enemey within melee range
    # @param source [Natural20::Entity]
    # @return [Boolean]
    def enemy_in_melee_range?(source, exclude = [])
      objects_around_me = map.look(source)

      objects_around_me.detect do |object, _|
        next if exclude.include?(object)

        state = entity_state_for(object)
        next unless state
        next unless object.conscious?

        return true if opposing?(source, object) && (map.distance(source,
                                                                  object) <= (object.melee_distance / map.feet_per_grid))
      end

      false
    end

    def ongoing?
      @started
    end

    def battle_ends?
      groups_present = @entities.keys.reject do |a|
                         a.dead? || a.unconscious?
                       end.map { |e| @entities[e][:group] }.uniq
      groups_present.each do |g|
        groups_present.each do |h|
          next if g == h
          raise "warning unknown group #{g}" unless @opposing_groups[g]
          return false if @opposing_groups[g].include?(h)
        end
      end
      true
    end

    def trigger_opportunity_attack(entity, target, cur_x, cur_y)
      event = {
        target: target,
        position: [cur_x, cur_y]
      }
      action = entity.trigger_event(:opportunity_attack, self, @session, @map, event)
      if action
        action.resolve(@session, @map, battle: self)
        commit(action)
      end
    end

    def commit(action)
      return if action.nil?

      # check_action_serialization(action)
      action.apply!(self)

      case action.action_type
      when :move
        trigger_event!(:movement, action.source, move_path: action.move_path)
      when :interact
        trigger_event!(:interact, action)
      end
      @battle_log << action
    end

    def trigger_event!(event, source, opt = {})
      @battle_field_events[event.to_sym]&.each do |object, handler|
        object.send(handler, self, source, opt.merge(ui_controller: controller_for(source)))
      end
      @map.activate_map_triggers(event, source, opt.merge(ui_controller: controller_for(source)))
    end

    protected

    def t(key, options = {})
      I18n.t(key, options)
    end

    def check_action_serialization(action)
      action.result.each do |r|
        r.each do |k, v|
          next if v.is_a?(String)
          next if v.is_a?(Integer)
          next if [true, false].include?(v)
          next if v.is_a?(Numeric)

          raise "#{action.action_type} value #{k} -> #{v} not serializable!"
        end
      end
    end
  end
end
