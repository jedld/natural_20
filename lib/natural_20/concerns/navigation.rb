module Natural20::Navigation
  include Natural20::Weapons

  # @param map [natural20::BattleMap]
  # @param battle [Natural20::Battle]
  # @param entity [Natural20::Entity]
  def candidate_squares(map, battle, entity)
    compute = AiController::PathCompute.new(battle, map, entity)
    cur_pos_x, cur_pos_y = map.entity_or_object_pos(entity)

    compute.build_structures(cur_pos_x, cur_pos_y)
    compute.path

    candidate_squares = [[[cur_pos_x, cur_pos_y], 0]]
    map.size[0].times.each do |pos_x|
      map.size[1].times.each do |pos_y|
        next unless map.line_of_sight_for?(entity, pos_x, pos_y)
        next unless map.placeable?(entity, pos_x, pos_y, battle)

        path, cost = compute.incremental_path(cur_pos_x, cur_pos_y, pos_x, pos_y)
        next if path.nil?

        candidate_squares << [[pos_x, pos_y], cost.floor]
      end
    end
    candidate_squares.uniq.to_h
  end

  # @param map [Natural20::BattleMap]
  # @param battle [Natural20::Battle]
  # @param entity [Natural20::Entity]
  # @param opponents [Array<Natural20::Entity>]
  def evaluate_square(map, battle, entity, opponents)
    melee_squares = opponents.map do |opp|
      opp.melee_squares(map)
    end.flatten(1)

    attack_options = if entity.npc?
                       entity.npc_actions.map do |npc_action|
                         next if npc_action[:ammo] && entity.item_count(npc_action[:ammo]) <= 0
                         next if  npc_action[:if] && !entity.eval_if(npc_action[:if])
                         next unless npc_action[:type] == 'melee_attack'

                         npc_action
                       end.first
                     end

    destinations = candidate_squares(map, battle, entity)
    destinations.map do |d, _cost|
      # evaluate defence
      melee_offence = 0.0
      ranged_offence = 0.0
      defence = 0.0
      mobility = 0.0
      support = 0.0

      if melee_squares.include?(d)
        melee_offence += 0.1
        if attack_options
          opponents.each do |opp|
            melee_offence += target_advantage_condition(battle, entity, opp, attack_options, source_pos: d)
          end
        end
      else
        ranged_offence += 0.1
        opponents.each do |opp|
          defence += map.cover_calculation_at_pos(map, opp, entity, d[0], d[1]).to_f
        end
      end

      if map.requires_squeeze?(entity, *d, map, battle)
        mobility -= 1.0
        melee_offence -= 0.5
        ranged_offence -= 0.5
      end

      [d, [melee_offence, ranged_offence, defence, mobility, support]]
    end.to_h
  end
end
