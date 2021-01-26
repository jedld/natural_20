module Natural20::Cover
  # @param map [Natural20::BattleMap]
  # @param source [Natural20::Entity]
  # @param target [Natural20::Entity]
  # @return [Integer]
  def cover_calculation(map, source, target)
    source_squares = map.entity_squares(source)
    target_squares = map.entity_squares(target)
    source_position = map.position_of(source)
    source_melee_square = source.melee_squares(map, target_position: source_position, adjacent_only: true)

    source_squares.map do |source_pos|
      target_squares.map do |target_pos|
        cover_characteristics = map.line_of_sight?(*source_pos, *target_pos, nil, true)
        next 0 unless cover_characteristics

        max_ac = 0
        cover_characteristics.each do |cover|
          cover_type, pos = cover
          next if cover_type == :none
          next if source_melee_square.include?(pos)

          max_ac = [max_ac, 2].max if cover_type == :half
          max_ac = [max_ac, 5].max if cover_type == :three_quarter
        end
        max_ac
      end.min
    end.min || 0
  end
end