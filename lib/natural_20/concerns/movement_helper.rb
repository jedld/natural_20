# typed: true
module Natural20::MovementHelper
  class Movement
    def initialize(movement, original_budget, acrobatics_check_locations, athletics_check_locations, jump_locations, jump_start_locations, land_locations, jump_budget, budget, impediment)
      @jump_start_locations = jump_start_locations
      @athletics_check_locations = athletics_check_locations
      @jump_locations = jump_locations
      @land_locations = land_locations
      @jump_budget = jump_budget
      @movement = movement
      @original_budget = original_budget
      @acrobatics_check_locations = acrobatics_check_locations
      @impediment = impediment
      @budget = budget
    end

    # @return [Natural20::Movement]
    def self.empty
      Movement.new([], 0, [], [], [], [], [], 0, 0, :nil)
    end

    # @return [Integer]
    attr_reader :budget

    # @return [Symbol]
    attr_reader :impediment

    # @return [Array]
    attr_reader :movement

    # @return [Integer]
    attr_reader :jump_budget

    # @return [Array]
    attr_reader :jump_start_locations

    # @return [Array]
    attr_reader :jump_locations

    # @return [Array]
    attr_reader :land_locations

    # @return [Array]
    attr_reader :acrobatics_check_locations

    # @return [Array]
    attr_reader :athletics_check_locations

    # @return [Integer]
    def cost
      (@original_budget - @budget)
    end
  end

  # Checks if move path is valid
  # @param entity [Natural20::Entity]
  # @param path [Array]
  # @param battle [Natural20::Battle]
  # @param map [Natural20::BattleMap]
  # @param test_placement [Boolean]
  # @param manual_jump [Array]
  # @return [Boolean]
  def valid_move_path?(entity, path, battle, map, test_placement: true, manual_jump: [])
    path == compute_actual_moves(entity, path, map, battle, entity.available_movement(battle) / map.feet_per_grid,
                                 test_placement: test_placement, manual_jump: manual_jump).movement
  end

  # Determine if entity needs to squeeze to get through terrain
  # @param entity [Natural20::Entity]
  # @param pos_x [Integer]
  # @param pos_y [Integer]
  # @param map [Natural20::BattleMap]
  # @param battle [Natural20::Battle]
  # @return [Boolean]
  def requires_squeeze?(entity, pos_x, pos_y, map, battle = nil)
    !map.passable?(entity, pos_x, pos_y, battle, false) && map.passable?(entity, pos_x, pos_y, battle, true)
  end

  # @param entity [Natural20::Entity]
  # @param current_moves [Array]
  # @param map [Natural20::BattleMap]
  # @param battle [Natural20::Battle]
  # @param movement_budget [Integer] movement budget in number of squares (feet/5 by default)
  # @param test_placement [Boolean] If true tests if last move is placeable on the map
  # @param manual_jump [Array] Indices of moves that are supposed to be jumps
  # @return [Movement]
  def compute_actual_moves(entity, current_moves, map, battle, movement_budget, fixed_movement: false, test_placement: true, manual_jump: [])
    actual_moves = []
    provisional_moves = []
    jump_budget = (entity.standing_jump_distance / map.feet_per_grid).floor
    running_distance = 1
    jump_distance = 0
    jumped = false
    acrobatics_check_locations = []
    athletics_check_locations = []
    jump_start_locations = []
    land_locations = []
    jump_locations = []
    impediment = nil
    original_budget = movement_budget

    current_moves.each_with_index do |m, index|
      unless index.positive?
        actual_moves << m
        next
      end

      unless map.passable?(entity, *m, battle)
        impediment = :path_blocked
        break
      end

      if fixed_movement
        movement_budget -= 1
      else
        movement_budget -= if !manual_jump.include?(index) && map.difficult_terrain?(entity, *m, battle)
                             2
                           else
                             1
                           end
        movement_budget -= 1 if requires_squeeze?(entity, *m, map, battle)
        movement_budget -= 1 if entity.prone?
        movement_budget -= 1 if entity.grappling?
      end

      if movement_budget.negative?
        impediment = :movement_budget
        break
      end

      if !fixed_movement && (map.jump_required?(entity, *m) || manual_jump.include?(index))
        if entity.prone? # can't jump if prone
          impediment = :prone_need_to_jump
          break
        end

        jump_start_locations << m unless jumped
        jump_locations << m
        jump_budget -= 1
        jump_distance += 1
        if !fixed_movement && jump_budget.negative?
          impediment = :jump_distance_not_enough
          break
        end

        running_distance = 0
        jumped = true
        provisional_moves << m

        entity_at_square = map.entity_at(*m)
        athletics_check_locations << m if entity_at_square&.conscious? && !entity_at_square&.prone?
      else
        actual_moves += provisional_moves
        provisional_moves.clear

        land_locations << m if jumped
        acrobatics_check_locations << m if jumped && map.difficult_terrain?(entity, *m,
                                                                            battle)
        running_distance += 1

        # if jump not required reset jump budgets
        jump_budget = if running_distance > 1
                        (entity.long_jump_distance / map.feet_per_grid).floor
                      else
                        (entity.standing_jump_distance / map.feet_per_grid).floor
                      end
        jumped = false
        jump_distance = 0
        actual_moves << m
      end
    end

    # handle case where end is a jump, in that case we land if this is possible
    unless provisional_moves.empty?
      actual_moves += provisional_moves
      m = actual_moves.last
      land_locations << m if jumped
      acrobatics_check_locations << m if jumped && map.difficult_terrain?(entity, *m,
                                                                          battle)
      jump_locations.delete(actual_moves.last)
    end

    while test_placement && !map.placeable?(entity, *actual_moves.last, battle)
      impediment = :not_placeable
      jump_locations.delete(actual_moves.last)
      actual_moves.pop
    end

    Movement.new(actual_moves, original_budget, acrobatics_check_locations, athletics_check_locations, jump_locations, jump_start_locations, land_locations, jump_budget,
                 movement_budget, impediment)
  end
end
