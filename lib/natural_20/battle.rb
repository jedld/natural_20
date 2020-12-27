class Battle
  attr_accessor :combat_order, :round
  attr_reader :map, :entities, :session, :battle_log, :started

  # Create an instance of a battle
  # @param session [Session]
  # @param map [BattleMap]
  def initialize(session, map)
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
  end

  def add_battlefield_event_listener(event, handler)
    @battle_field_events[event.to_sym] ||= []
    @battle_field_events[event.to_sym] << handler
  end

  # Adds an entity to the battle
  # @param entity [Entity] The entity to add to the battle
  # @param group [Symbol] A symbol denoting which group this entity belongs to
  # @param position [Array, Symbol] Starting location in the map can be a position or a spawn point
  # @param token [String, Symbol] The token to use
  def add(entity, group, position: nil, token: nil)
    return if @entities[entity]

    raise 'entity cannot be nil' if entity.nil?

    @entities[entity] = {
      group: group,
      action: 0,
      bonus_action: 0,
      reaction: 0,
      movement: 0,
      statuses: Set.new,
      free_object_interaction: 0,
      target_effect: {}
    }

    @groups[group] ||= Set.new
    @groups[group].add(entity)

    # battle already ongoing...
    if started
      @late_comers << entity
      @entities[entity][:initiative] = entity.initiative!
    end

    return if position.nil?
    return if @map.nil?

    position.is_a?(Array) ? @map.place(*position, entity, token) : @map.place_at_spawn_point(position, entity, token)
  end

  def in_battle?(entity)
    @entities.key?(entity)
  end

  # @param entity [Entity]
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

  # Targets that make sense for a given action
  # @param entity [Entity]
  # @param action [Action]
  # @return [Entity]
  def valid_targets_for(entity, action, target_types: [:enemies], range: nil, include_objects: false)
    raise 'not an action' unless action.is_a?(Action)

    target_types = target_types&.map(&:to_sym) || [:enemies]
    entity_group = @entities[entity][:group]
    attack_range = if action.action_type == :help
                     5
                   elsif action.action_type == :attack
                     if action.npc_action
                       action.npc_action[:range_max].presence || action.npc_action[:range]
                     elsif action.using
                       weapon = Session.load_weapon(action.using)
                       weapon[:range_max].presence || weapon[:range]
                     end
                   else
                     range
                   end

    raise 'attack range cannot be nil' if attack_range.nil?

    targets = @entities.map do |k, prop|
      next if !target_types.include?(:self) && k == entity
      next if !target_types.include?(:allies) && prop[:group] == entity_group && k != entity
      next if !target_types.include?(:enemies) && prop[:group] != entity_group
      next if k.dead?
      next if !target_types.include?(:ignore_los) && !@map.line_of_sight_for_ex?(entity, k)
      next if @map.distance(k, entity) * 5 > attack_range

      k
    end.compact

    if include_objects
      targets += @map.interactable_objects.map do |object, _position|
        next if object.dead?
        next if !target_types.include?(:ignore_los) && !@map.line_of_sight_for_ex?(entity, object)
        next if @map.distance(object, entity) * 5 > attack_range

        object
      end.compact
    end

    targets
  end

  def opponents_of?(entity)
    source_state = entity_state_for(entity)
    source_group = source_state[:group]

    opponents = []
    @entities.each do |k, state|
      opponents << k  if !k.dead? && state[:group] != source_group
    end
    opponents
  end

  # consume action resource and return if something changed
  def consume!(entity, resource, qty)
    current_qty = entity_state_for(entity)[resource.to_sym]
    new_qty = [0, current_qty - qty].max
    entity_state_for(entity)[resource.to_sym] = new_qty

    current_qty != new_qty
  end

  def start
    # roll for initiative
    @combat_order = @entities.map do |entity, v|
      v[:initiative] = entity.initiative!

      entity
    end

    @started = true
    @combat_order = @combat_order.sort_by { |a| @entities[a][:initiative] }.reverse
  end

  def current_turn
    @combat_order[@current_turn_index]
  end

  def while_active(max_rounds = nil, &block)
    loop do
      EventManager.received_event({ source: self, event: :start_of_round, target: current_turn })
      if current_turn.concious?
        current_turn.reset_turn!(self)
        block.call(current_turn)
      end

      trigger_event!(:end_of_round, self, target: current_turn)

      @current_turn_index += 1
      if @current_turn_index >= @combat_order.length
        @current_turn_index = 0
        @round += 1

        # top of the round

        @combat_order += @late_comers
        @late_comers.clear
        @combat_order = @combat_order.sort_by { |a| @entities[a][:initiative] }.reverse

        EventManager.received_event({ source: self, event: :top_of_the_round, round: @round, target: current_turn })

        return if !max_rounds.nil? && @round > max_rounds
      end
      break if battle_ends?
    end
  end

  def enemy_in_melee_range?(source, exclude = [])
    objects_around_me = map.look(source)

    my_group = entity_group_for(source)

    objects_around_me.detect do |object, _|
      next if exclude.include?(object)

      state = entity_state_for(object)
      next unless state
      next unless object.concious?

      return true if state[:group] != my_group && (map.distance(source, object) <= (object.melee_distance / 5))
    end

    false
  end

  def battle_ends?
    live_groups = @combat_order.reject { |a| a.dead? || a.unconcious? }.map { |e| @entities[e][:group] }.uniq
    live_groups.size <= 1
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
    end
    @battle_log << action
  end

  protected

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

  def trigger_event!(event, source, opt = {})
    @battle_field_events[event.to_sym]&.each do |handler|
      handler.call(source, opt)
    end
  end
end
