# typed: false
module AiController
  # Class used for handling "Standard" NPC AI
  class Standard < Natural20::Controller
    include Natural20::MovementHelper

    attr_reader :battle_data

    def initialize
      @battle_data = {}
    end

    def sound_listener(battle, entity, position, stealth); end

    # @param battle [Natural20::Battle]
    # @param entity [Natural20::Entity]
    # @param position [Array]
    def movement_listener(battle, entity, position)
      move_path = position[:move_path]

      return if move_path.nil?

      # handle unaware npcs
      new_npcs = battle.map.unaware_npcs.map do |unaware_npc_info|
        npc = unaware_npc_info[:entity]
        seen = !!move_path.reverse.detect do |path|
          npc.conscious? && battle.map.can_see?(npc, entity, entity_2_pos: path)
        end

        next unless seen

        register_handlers_on(npc) # attach this AI controller to this NPC
        battle.add(npc, unaware_npc_info[:group])
        npc
      end.compact
      new_npcs.each { |npc| battle.map.unaware_npcs.delete(npc) }

      # update seen info for each npc
      battle.entities.each_key do |e|
        loc = move_path.reverse.detect do |location|
          battle.map.can_see?(entity, e, entity_2_pos: location)
        end
        # include friendlies as well since they can turn on us at one point in time :)
        update_enemy_known_position(e, entity, *loc) if loc
      end
    end

    def attack_listener(battle, _action, _source, target)
      unaware_npc_info = battle.map.unaware_npcs.detect { |n| n[:entity] == target }
      return unless unaware_npc_info

      register_handlers_on(target) # attach this AI controller to this NPC
      battle.add(target, unaware_npc_info[:group])
      battle.map.unaware_npcs.delete(target)
    end

    # @param battle [Natural20::Battle]
    # @param action [Natural20::Action]
    def action_listener(battle, action, _opt)
      # handle unaware npcs
      new_npcs = battle.map.unaware_npcs.map do |unaware_npc_info|
        npc = unaware_npc_info[:entity]
        next unless npc.conscious?
        next unless battle.map.can_see?(npc, action.source)

        register_handlers_on(npc) # attach this AI controller to this NPC
        battle.add(npc, unaware_npc_info[:group])
        update_enemy_known_position(battle, npc, action.source, battle.map.entity_squares(action.source).first)
        npc
      end
      new_npcs.each { |npc| battle.map.unaware_npcs.delete(npc) }
    end

    def opportunity_attack_listener(battle, session, entity, map, event)
      entity_x, entity_y = map.position_of(entity)
      target_x, target_y = event[:position]

      distance = Math.sqrt((target_x - entity_x)**2 + (target_y - entity_y)**2).ceil

      action = entity.available_actions(session, battle).select do |s|
        s.action_type == :attack && s.npc_action[:type] == 'melee_attack' && distance <= s.npc_action[:range]
      end.first

      if action
        action.target = event[:target]
        action.as_reaction = true
      end
      action
    end

    def register_battle_listeners(battle)
      # detects noisy things
      battle.add_battlefield_event_listener(:sound, self, :sound_listener)

      # detects line of sight movement
      battle.add_battlefield_event_listener(:movement, self, :movement_listener)

      # actions listener (check if doors opened etc)
      battle.add_battlefield_event_listener(:interact, self, :action_listener)
    end

    # @param entity [Natural20::Entity]
    def register_handlers_on(entity)
      entity.attach_handler(:opportunity_attack, self, :opportunity_attack_listener)
    end

    # tests if npc has an appropriate weapon to at least one visible enemy
    def has_appropriate_weapon?; end

    # Tells AI to compute moves for an entity
    # @param entity [Natural20::Entity] The entity to compute moves for
    # @param battle [Natural20::Battle] An instance of the current battle
    # @return [Array]
    def move_for(entity, battle)
      initialize_battle_data(battle, entity)

      known_enemy_positions = @battle_data[battle][entity][:known_enemy_positions]
      hiding_spots = @battle_data[battle][entity][:hiding_spots]
      investigate_location = @battle_data[battle][entity][:investigate_location]

      enemy_positions = {}
      observe_enemies(battle, entity, enemy_positions)

      available_actions = entity.available_actions(@session, battle)

      # generate available targets
      valid_actions = []

      # try to stand if prone
      valid_actions << StandAction.new(@session, entity, :stand) if entity.prone? && StandAction.can?(entity, battle)

      available_actions.select { |a| a.action_type == :attack }.each do |action|
        next unless action.npc_action

        valid_targets = battle.valid_targets_for(entity, action)
        unless valid_targets.first.nil?
          action.target = valid_targets.first
          valid_actions << action
        end
      end

      # movement planner if no more attack options and enemies are in sight
      if valid_actions.empty? && !enemy_positions.empty?
        valid_actions += generate_moves_for_positions(battle, entity, enemy_positions)
      end

      # attempt to investigate last seen positions
      if enemy_positions.empty?
        my_group = battle.entity_group_for(entity)
        investigate_location = known_enemy_positions.map do |enemy, position|
          group = battle.entity_group_for(enemy)
          next if my_group == group

          position
        end.compact

        valid_actions += generate_moves_for_positions(battle, entity, investigate_location)
      end

      valid_actions << DodgeAction.new(battle.session, entity, :dodge) if entity.action?(battle)

      return valid_actions.first unless valid_actions.empty?
    end

    protected

    # @param battle [Natural20::Battle]
    # @param entity [Natural20::Entity]
    # @param enemy_positions [Hash]
    # @param use_dash [Boolean]
    def generate_moves_for_positions(battle, entity, enemy_positions, use_dash: false)
      valid_actions = []

      path_compute = PathCompute.new(battle, battle.map, entity)
      start_x, start_y = battle.map.position_of(entity)
      to_enemy = enemy_positions.map do |k, v|
        melee_positions = entity.locate_melee_positions(battle.map, v, battle)
        shortest_path = nil
        shortest_length = 1_000_000

        melee_positions.each do |positions|
          path = path_compute.compute_path(start_x, start_y, *positions)
          next if path.nil?

          movement_cost = battle.map.movement_cost(entity, path, battle)
          if movement_cost.cost * battle.map.feet_per_grid < shortest_length
            shortest_path = path
            shortest_length = path.size
          end
        end
        [k, shortest_path]
      end.compact.to_h

      to_enemy.each do |_, path|
        next if path.nil? || path.empty?

        if entity.available_movement(battle).zero? && use_dash
          if DashBonusAction.can?(entity, battle)
            action DashBonusAction.new(battle.session, entity, :dash_bonus)
            action.as_bonus_action = true
            valid_actions <<  action
          elsif DashAction.can?(entity, battle)
            valid_actions << DashAction.new(battle.session, entity, :dash)
          end
        elsif MoveAction.can?(entity, battle)
          move_action = MoveAction.new(battle.session, entity, :move)
          move_budget = entity.available_movement(battle) / battle.map.feet_per_grid
          path = compute_actual_moves(entity, path, battle.map, battle, move_budget).movement
          next if path.size.zero? || path.size == 1

          move_action.move_path = path
          valid_actions << move_action
        end
      end

      valid_actions
    end

    # gain information about enemies in a fair and realistic way (e.g. using line of sight)
    # @param battle [Natural20::Battle]
    # @param entity [Natural20::Entity]
    def observe_enemies(battle, entity, enemy_positions = {})
      objects_around_me = battle.map.look(entity)

      my_group = battle.entity_group_for(entity)

      objects_around_me.each do |object, location|
        group = battle.entity_group_for(object)
        next if group == :none
        next unless group
        next unless object.conscious?

        enemy_positions[object] = location if group != my_group
      end
    end

    # @param battle [Natural20::Battle]
    # @param entity [Natural20::Entity]
    # @param enemy  [Natural20::Entity]
    # @param position [Array]
    def update_enemy_known_position(battle, entity, enemy, position)
      initialize_battle_data(battle, entity)

      @battle_data[battle][entity][:known_enemy_positions][enemy] = position
    end

    def initialize_battle_data(battle, entity)
      @battle_data[battle] ||= {}
      @battle_data[battle][entity] ||= {
        known_enemy_positions: {},
        hiding_spots: {},
        investigate_location: {}
      }
    end
  end
end
