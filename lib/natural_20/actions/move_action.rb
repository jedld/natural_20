# typed: true
class MoveAction < Natural20::Action
  include Natural20::MovementHelper
  extend Natural20::ActionDamage

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

    safe_moves = []
    actual_moves.each_with_index do |move, _index|
      is_flying_or_jumping = @source.flying? || movement.jump_locations.include?(move)
      trigger_results = map.area_trigger!(@source, move, is_flying_or_jumping)
      if trigger_results.empty?
        safe_moves << move
      else
        safe_moves << move
        additional_effects += trigger_results
        break
      end
    end

    movement = compute_actual_moves(@source, safe_moves, map, battle, movement_budget, manual_jump: jumps)

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
          as_dash: as_dash,
          as_bonus_action: as_bonus_action,
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
      as_dash: as_dash,
      as_bonus_action: as_bonus_action,
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
    if battle

      retrieve_opportunity_attacks(entity, move_list, battle).each do |enemy_opporunity|
        original_location = move_list[0...enemy_opporunity[:path]]
        attack_location = original_location.last
        battle.trigger_opportunity_attack(enemy_opporunity[:source], entity, *attack_location)

        return original_location if !grappled && !entity.conscious?
      end
    end
    move_list
  end

  def self.apply!(battle, item)
      case (item[:type])
      when :state
        item[:params].each do |k, v|
          item[:source].send(:"#{k}=", v)
        end
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
        if item[:as_dash] && item[:as_bonus_action]
          battle.entity_state_for(item[:source])[:bonus_action] -= 1
        elsif item[:as_dash]
          battle.entity_state_for(item[:source])[:action] -= 1
        elsif battle
          battle.entity_state_for(item[:source])[:movement] -= item[:move_cost] * battle.map.feet_per_grid
        end

        Natural20::EventManager.received_event({ event: :move, source: item[:source], position: item[:position], path: item[:path],
                                                 feet_per_grid: battle.map&.feet_per_grid,
                                                 as_dash: item[:as_dash], as_bonus: item[:as_bonus_action] })
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
