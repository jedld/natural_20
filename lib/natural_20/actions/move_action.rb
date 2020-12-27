class MoveAction < Action
  include MovementHelper

  attr_accessor :move_path, :as_dash, :as_bonus_action

  def self.can?(entity, battle)
    battle.nil? || entity.available_movement(battle) > 0
  end

  def build_map
    OpenStruct.new({
                     action: self,
                     param: [
                       {
                         type: :movement
                       }
                     ],
                     next: lambda { |path|
                             self.move_path = path
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

  def resolve(_session, map, opts = {})
    raise 'no path specified' if (move_path.nil? || move_path.empty?) && opts[:move_path].nil?

    # check for melee opportunity attacks
    battle = opts[:battle]

    current_moves = move_path.presence || opts[:move_path]

    actual_moves = []

    movement_budget = if as_dash
                        @source.speed / 5
                      else
                        @source.available_movement(battle)
                      end

    actual_moves = compute_actual_moves(@source, current_moves, map, battle, movement_budget)

    actual_moves.pop while actual_moves.last && !map.placeable?(@source, *actual_moves.last, battle)

    if battle && !@source.disengage?(battle)
      opportunity_attacks = opportunity_attack_list(actual_moves, battle, map)
      opportunity_attacks.each do |enemy_opporunity|
        next unless enemy_opporunity[:source].has_reaction?(battle)

        original_location = actual_moves[enemy_opporunity[:path] - 1]
        battle.trigger_opportunity_attack(enemy_opporunity[:source], @source, *original_location)

        unless @source.concious?
          actual_moves = original_location
          break
        end
      end
    end

    @result = [{
      source: @source,
      map: map,
      battle: battle,
      type: :move,
      path: actual_moves,
      position: actual_moves.last
    }]

    self
  end

  def opportunity_attack_list(current_moves, battle, map)
    # get opposing forces
    opponents = battle.opponents_of?(@source)
    entered_melee_range = Set.new
    left_melee_range = []
    current_moves.each_with_index do |path, index|
      opponents.each do |enemy|
        entered_melee_range.add(enemy) if enemy.entered_melee?(map, @source, *path)
        if !left_melee_range.include?(enemy) && entered_melee_range.include?(enemy) && !enemy.entered_melee?(map, @source, *path)
          left_melee_range << { source: enemy, path: index }
        end
      end
    end
    left_melee_range
  end

  def apply!(battle)
    @result.each do |item|
      case (item[:type])
      when :move
        item[:map].move_to!(item[:source], *item[:position])
        if as_dash && as_bonus_action
          battle.entity_state_for(item[:source])[:bonus_action] -= 1
        elsif as_dash
          battle.entity_state_for(item[:source])[:action] -= 1
        elsif battle
          battle.entity_state_for(item[:source])[:movement] -= battle.map.movement_cost(item[:source], item[:path], battle)
        end

        EventManager.received_event({ event: :move, source: item[:source], position: item[:position], path: item[:path],
                                      as_dash: as_dash, as_bonus: as_bonus_action })
      end
    end
  end
end
