module AiController
  class Standard
    include MovementHelper

    attr_reader :battle_data
    def initialize
      @battle_data = {}
    end

    def register_battle_listeners(battle)
      # detects noisy things
      battle.add_battlefield_event_listener(:sound, lambda { |entity, position, stealth|
      })

      # detects line of sight movement
      battle.add_battlefield_event_listener(:movement, lambda { |entity, position|
        move_path = position[:move_path]

        return if move_path.nil?

        # handle unaware npcs

        new_npcs = battle.map.unaware_npcs.map do |npc|
          npc_position = position_of(npc)
          move_path.reverse.detect do |path|
            if battle.map.line_of_sight?(*npc_position, *path) && !battle.in_battle?(npc)
              battle.add(npc, npc.group)
              npc
            end
          end
        end.compact
        new_npcs.each { |npc| battle.map.unaware_npcs.delete(npc) }

        # update seen info for each npc
        battle.entities.keys.each do |e|
          current_position = battle.map.position_of(e)
          loc = move_path.reverse.detect do |location|
            e.can_see?(*current_position, entity, *location, battle)
          end
          update_enemy_known_position(e, entity, *loc) if loc
        end
      })
    end

    def register_handlers_on(entity)
      entity.attach_handler(:opportunity_attack, lambda { |battle, session, map, event|
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
      })
    end

    # Tells AI to compute moves for an entity
    # @param entity [Entity] The entity to compute moves for
    # @param battle [Battle] An instance of the current battle
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

      available_actions.select { |a| a.action_type == :attack }.each do |action|
        next unless action.npc_action

        valid_targets = battle.valid_targets_for(entity, action)
        unless valid_targets.first.nil?
          action.target = valid_targets.first
          valid_actions << action
        end
      end

      # movement planner
      if valid_actions.empty? && !enemy_positions.empty?
        valid_actions += generate_moves_for_positions(battle, entity, enemy_positions, use_dash: true)
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
          if movement_cost < shortest_length
            shortest_path = path
            shortest_length = path.size
          end
        end
        [k, shortest_path]
      end.compact.to_h

      to_enemy.each do |_, path|
        next if path.nil? || path.empty?

        move_action = MoveAction.new(battle.session, entity, :move)
        if entity.available_movement(battle).zero? && use_dash
          move_action.as_dash = true
          path = compute_actual_moves(entity, path, battle.map, battle, entity.speed)
        else
          move_budget = entity.available_movement(battle)
          path = compute_actual_moves(entity, path, battle.map, battle, move_budget)
        end

        next if path.size.zero? || path.size == 1

        move_action.move_path = path
        valid_actions << move_action
      end

      valid_actions
    end

    # gain information about enemies in a fair and realistic way (e.g. using line of sight)
    # @param battle [Battle]
    # @param entity [Entity]
    def observe_enemies(battle, entity, enemy_positions = {})
      objects_around_me = battle.map.look(entity)

      my_group = battle.entity_group_for(entity)

      objects_around_me.each do |object, location|
        group = battle.entity_group_for(object)
        next if group == :none
        next unless group
        next unless object.concious?

        enemy_positions[object] = location if group != my_group
      end
    end

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
