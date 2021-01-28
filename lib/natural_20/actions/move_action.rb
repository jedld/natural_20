# typed: true
class MoveAction < Natural20::Action
  include Natural20::MovementHelper

  attr_accessor :move_path, :jump_index, :as_dash, :as_bonus_action

  def self.can?(entity, battle)
    battle.nil? || entity.available_movement(battle).positive?
  end

  def build_map
    OpenStruct.new({
                     action: self,
                     param: [
                       {
                         type: :movement
                       }
                     ],
                     next: lambda { |path_and_jump_index|
                       path, jump_index = path_and_jump_index
                       self.move_path = path
                       self.jump_index = jump_index
                       OpenStruct.new({
                                        param: nil,
                                        next: -> { self }
                                      })
                     }
                   })
  end

  def self.build(session, source)
    action = MoveAction.new(session, source, :move)
    action.build_map
  end

  # @param map [Natural20::BattleMap]
  # @option opts battle [Natural20::Battle]
  def resolve(_session, map, opts = {})
    raise 'no path specified' if (move_path.nil? || move_path.empty?) && opts[:move_path].nil?

    @result = []
    # check for melee opportunity attacks
    battle = opts[:battle]

    current_moves = move_path.presence || opts[:move_path]
    jumps = jump_index || []

    actual_moves = []
    additional_effects = []

    movement_budget = if as_dash
                        (@source.speed / 5).floor
                      else
                        (@source.available_movement(battle) / 5).floor
                      end

    movement = compute_actual_moves(@source, current_moves, map, battle, movement_budget, manual_jump: jumps)
    actual_moves = movement.movement

    actual_moves.pop while actual_moves.last && !map.placeable?(@source, *actual_moves.last, battle)

    actual_moves = check_opportunity_attacks(@source, actual_moves, battle)

    # check if movement requires athletics checks
    actual_moves = check_movement_athletics(actual_moves, movement.athletics_check_locations, battle, map)

    # check if movement requires dex checks, e.g. jumping and landing on difficult terrain
    actual_moves = check_movement_acrobatics(actual_moves, movement.acrobatics_check_locations, battle)

    # calculate for area based triggers
    cutoff = false

    actual_moves = actual_moves.each_with_index.map do |move, _index|
      is_flying_or_jumping = movement.jump_locations.include?(move)
      trigger_results = map.area_trigger!(@source, move, is_flying_or_jumping)
      if trigger_results.empty?
        cutoff ? nil : move
      else
        cutoff = true
        additional_effects += trigger_results
        move
      end
    end.compact

    movement = compute_actual_moves(@source, actual_moves, map, battle, movement_budget, manual_jump: jumps)

    # compute grappled entity movement
    if @source.grappling?
      grappled_movement = movement.movement.dup
      grappled_movement.pop

      @source.grappling_targets.each do |grappling_target|
        start_pos = map.entity_or_object_pos(grappling_target)
        grappled_entity_movement = [start_pos] + grappled_movement

        additional_effects << {
          source: grappling_target,
          map: map,
          battle: battle,
          type: :move,
          path: grappled_entity_movement,
          move_cost: 0,
          position: grappled_entity_movement.last
        }

        grappled_movement.pop
      end
    end

    @result << {
      source: @source,
      map: map,
      battle: battle,
      type: :move,
      path: movement.movement,
      move_cost: movement_budget - movement.budget,
      position: movement.movement.last
    }
    @result += additional_effects

    self
  end

  # @param entity [Natural20::Entity]
  # @param move_list [Array<Array<Integer,Integer>>]
  # @param battle [Natural20::Battle]
  def check_opportunity_attacks(entity, move_list, battle, grappled: false)
    if battle && !@source.disengage?(battle)
      opportunity_attacks = opportunity_attack_list(entity, move_list, battle, battle.map)
      opportunity_attacks.each do |enemy_opporunity|
        next unless enemy_opporunity[:source].has_reaction?(battle)

        original_location = move_list[enemy_opporunity[:path] - 1]
        battle.trigger_opportunity_attack(enemy_opporunity[:source], entity, *original_location)

        if !grappled && !entity.conscious?
          move_list = original_location
          break
        end
      end
    end
    move_list
  end

  def opportunity_attack_list(entity, current_moves, battle, map)
    # get opposing forces
    opponents = battle.opponents_of?(entity)
    entered_melee_range = Set.new
    left_melee_range = []
    current_moves.each_with_index do |path, index|
      opponents.each do |enemy|
        entered_melee_range.add(enemy) if enemy.entered_melee?(map, entity, *path)
        if !left_melee_range.include?(enemy) && entered_melee_range.include?(enemy) && !enemy.entered_melee?(map,
                                                                                                             entity, *path)
          left_melee_range << { source: enemy, path: index }
        end
      end
    end
    left_melee_range
  end

  def apply!(battle)
    @result.each do |item|
      case (item[:type])
      when :state
        item[:params].each do |k, v|
          item[:source].send(:"#{k}=", v)
        end
      when :damage
        Natural20::EventManager.received_event({ source: item[:source], attack_roll: item[:attack_roll], target: item[:target], event: :attacked,
                                                 attack_name: item[:attack_name],
                                                 damage_type: item[:damage_type],
                                                 damage_roll: item[:damage],
                                                 value: item[:damage].result })
        item[:target].take_damage!(item, battle)
      when :acrobatics, :athletics
        if item[:success]
          Natural20::EventManager.received_event(source: item[:source], event: item[:type], success: true,
                                                 roll: item[:roll])
        else
          Natural20::EventManager.received_event(source: item[:source], event: item[:type], success: false,
                                                 roll: item[:roll])
          item[:source].prone!
        end
      when :drop_grapple
        item[:target].escape_grapple_from!(@source)
        Natural20::EventManager.received_event(event: :drop_grapple,
                                               target: item[:target], source: @source,
                                               source_roll: item[:source_roll],
                                               target_roll: item[:target_roll])

      when :move
        item[:map].move_to!(item[:source], *item[:position], battle)
        if as_dash && as_bonus_action
          battle.entity_state_for(item[:source])[:bonus_action] -= 1
        elsif as_dash
          battle.entity_state_for(item[:source])[:action] -= 1
        elsif battle
          battle.entity_state_for(item[:source])[:movement] -= item[:move_cost] * battle.map.feet_per_grid
        end

        Natural20::EventManager.received_event({ event: :move, source: item[:source], position: item[:position], path: item[:path],
                                                 feet_per_grid: battle.map&.feet_per_grid,
                                                 as_dash: as_dash, as_bonus: as_bonus_action })
      end
    end
  end

  private

  # @param actual_moves [Array]
  # @param dexterity_checks [Array]
  # @param battle [Natural20::Battle]
  # @return [Array]
  def check_movement_acrobatics(actual_moves, dexterity_checks, battle)
    cutoff = actual_moves.size - 1
    actual_moves.each_with_index do |m, index|
      next unless dexterity_checks.include?(m)

      acrobatics_roll = @source.acrobatics_check!(battle)
      if acrobatics_roll.result >= 10
        @result << { source: @source, type: :acrobatics, success: true, roll: acrobatics_roll, location: m }
      else
        @result << { source: @source, type: :acrobatics, success: false, roll: acrobatics_roll, location: m }
        cutoff = index
        break
      end
    end
    actual_moves[0..cutoff]
  end

  # @param actual_moves [Array]
  # @param athletics_checks [Array]
  # @param battle [Natural20::Battle]
  # @param map [Natural20::BattleMap]
  # @return [Array]
  def check_movement_athletics(actual_moves, athletics_checks, battle, map)
    cutoff = actual_moves.size - 1
    actual_moves.each_with_index do |m, index|
      next unless athletics_checks.include?(m)

      athletics_roll = @source.athletics_check!(battle)
      if athletics_roll.result >= 10
        @result << { source: @source, type: :athletics, success: true, roll: athletics_roll, location: m }
      else
        @result << { source: @source, type: :athletics, success: false, roll: athletics_roll, location: m }
        cutoff = index - 1
        cutoff -= 1 while cutoff >= 0 && !map.placeable?(@source, *actual_moves[cutoff], battle)
        break
      end
    end

    actual_moves[0..cutoff]
  end
end
