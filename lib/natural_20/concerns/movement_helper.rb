module MovementHelper
  def compute_actual_moves(entity, current_moves, map, battle, movement_budget)
    actual_moves = []
    current_moves.each_with_index do |m, index|
      if index.positive?
        movement_budget -= if map.difficult_terrain?(entity, *m, battle)
                             2
                           else
                             1
                           end
      end

      break if movement_budget.negative?

      actual_moves << m
    end

    actual_moves.pop unless map.placeable?(entity, *actual_moves.last, battle)

    actual_moves
  end
end