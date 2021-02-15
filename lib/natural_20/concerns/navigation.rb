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
    melee_attack_squares = {}
    vulnerable_squares = {}

    opponents.each do |opp|
      map.entity_squares(opp).each do |pos|
        melee_attack_squares[pos] ||= 0
        melee_attack_squares[pos] += 1
      end
    end

    opponents.each do |opp|
      opp.melee_squares(map, adjacent_only: true).each do |pos|
        vulnerable_squares[pos] ||= 0
        vulnerable_squares[pos] += 1
      end
    end

    attack_options = if entity.npc?
                       entity.npc_actions.map do |npc_action|
                         next if npc_action[:ammo] && entity.item_count(npc_action[:ammo]) <= 0
                         next if npc_action[:if] && !entity.eval_if(npc_action[:if])
                         next unless npc_action[:type] == 'melee_attack'

                         npc_action
                       end.first
                     end

    destinations = candidate_squares(map, battle, entity)
    destinations.map do |d, _cost|
      # evaluate defense
      melee_offence = 0.0
      ranged_offence = 0.0
      defense = 0.0
      mobility = 0.0
      support = 0.0

      entity_melee_squares = entity.melee_squares(map, target_position: d, adjacent_only: true)

      defense -= 0.05 * vulnerable_squares[d] if vulnerable_squares.key?(d)

      if entity_melee_squares.detect { |p| melee_attack_squares.key?(p) }
        melee_offence += 0.2
        if attack_options
          opponents.each do |opp|
            adv, _adv_info = target_advantage_condition(battle, entity, opp, attack_options, source_pos: d)
            melee_offence += adv
          end
        end
      else
        ranged_offence += 0.1
        opponents.each do |opp|
          defense += map.cover_calculation(map, opp, entity, entity_2_pos: d,
                                                             naturally_stealthy: entity.class_feature?('naturally_stealthy')).to_f
        end
      end

      if map.requires_squeeze?(entity, *d, map, battle)
        mobility -= 1.0
        melee_offence -= 0.5
        ranged_offence -= 0.5
      end

      mobility -= 0.001 * map.line_distance(entity, *d)
      [d, [melee_offence, ranged_offence, defense, mobility, support]]
    end.to_h
  end
end
