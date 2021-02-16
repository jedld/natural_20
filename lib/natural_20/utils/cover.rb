module Natural20::Cover
  # @param map [Natural20::BattleMap]
  # @param source [Natural20::Entity]
  # @param target [Natural20::Entity]
  # @param entity_1_pos [Array<Integer,Integer>]
  # @param entity_2_pos [Array<Integer,Integer>]
  # @return [Integer]
  def cover_calculation(map, source, target, entity_1_pos: nil, entity_2_pos: nil, naturally_stealthy: false)
    source_squares = entity_1_pos ? map.entity_squares_at_pos(source, *entity_1_pos) : map.entity_squares(source)
    target_squares = entity_2_pos ? map.entity_squares_at_pos(target, *entity_2_pos) : map.entity_squares(target)
    source_position = map.position_of(source)
    source_melee_square = source.melee_squares(map, target_position: source_position, adjacent_only: true)

    source_squares.map do |source_pos|
      target_squares.map do |target_pos|
        cover_characteristics = map.line_of_sight?(*source_pos, *target_pos, inclusive: true, entity: naturally_stealthy)
        next 0 unless cover_characteristics

        max_ac = 0

        # check if any objects in the area provide cover
        objs = map.objects_at(*target_pos)
        objs.each do |object|
          max_ac = [max_ac, object.cover_ac].max if object.can_hide?
        end

        cover_characteristics.each do |cover|
          cover_type, pos = cover

          next if cover_type == :none
          next if source_melee_square.include?(pos)

          max_ac = [max_ac, 2].max if cover_type == :half
          max_ac = [max_ac, 5].max if cover_type == :three_quarter

          return 1 if cover_type.is_a?(Integer) && naturally_stealthy && (cover_type - target.size_identifier) >= 1
        end
        max_ac
      end.min
    end.min || 0
  end
end
