module Natural20
  class StaticLightBuilder
    attr_reader :lights

    # @param battlemap [Natural20::BattleMap] location of the map yml file
    def initialize(battlemap)
      @map = battlemap
      @properties = battlemap.properties
      @light_properties = @properties[:lights]
      @light_map = @properties.dig(:map, :light)
      @base_illumniation = @properties.dig(:map, :illumination) || 1.0
      @lights = []
      if @light_map && @light_properties
        @light_map.each_with_index do |row, cur_y|
          row.each_char.map(&:to_sym).each_with_index do |key, cur_x|
            next unless @light_properties[key]

            @lights << {
              position: [cur_x, cur_y]
            }.merge(@light_properties[key])
          end
        end
      end
    end

    def build_map
      max_x, max_y = @map.size
      max_y.times.map do |y|
        max_x.times.map do |x|
          @lights.inject(@base_illumniation) do |intensity, light|
            light_pos_x, light_pos_y = light[:position]
            bright_light = light.fetch(:bright, 10) / @map.feet_per_grid
            dim_light = light.fetch(:dim, 5) / @map.feet_per_grid

            intensity + if @map.line_of_sight?(x, y, light_pos_x, light_pos_y, bright_light, false)
                          1.0
                        elsif @map.line_of_sight?(x, y, light_pos_x, light_pos_y, bright_light + dim_light, false)
                          0.5
                        else
                          0.0
                        end
          end
        end
      end.transpose
    end

    # @param pos_x [Integer]
    # @parma pos_y [Integer]
    # @return [Float]
    def light_at(pos_x, pos_y)
      (@map.entities.keys + @map.interactable_objects.keys).inject(0.0) do |intensity, entity|
        next intensity if entity.light_properties.nil?

        light = entity.light_properties
        bright_light = light.fetch(:bright, 0.0) / @map.feet_per_grid
        dim_light = light.fetch(:dim, 0.0) / @map.feet_per_grid

        next intensity if (bright_light + dim_light) <= 0.0

        light_pos_x, light_pos_y = @map.entity_or_object_pos(entity)

        intensity + if @map.line_of_sight?(pos_x, pos_y, light_pos_x, light_pos_y, bright_light, false)
                      1.0
                    elsif @map.line_of_sight?(pos_x, pos_y, light_pos_x, light_pos_y, bright_light + dim_light, false)
                      0.5
                    else
                      0.0
                    end
      end
    end
  end
end
