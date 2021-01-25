module Natural20
  class MapRenderer
    DEFAULT_TOKEN_COLOR = :cyan
    attr_reader :map, :battle

    # @param map [Natural20::BattleMap]
    def initialize(map, battle = nil)
      @map = map
      @battle = battle
    end

    # Renders the current map to a string
    # @param line_of_sight [Array,Natural20::Entity] Entity or entities to consier line of sight rendering for
    # @param path [Array] Array of path to render movement
    # @param select_pos [Array] coordinate position to render selection cursor
    # @param update_on_drop [Boolean] If true, only render line of sight if movement has been confirmed
    # @return [String]
    def render(entity: nil, line_of_sight: nil, path: [], acrobatics_checks: [], athletics_checks: [], select_pos: nil, update_on_drop: true, highlight: {})
      highlight_positions = highlight.keys.map { |entity| @map.entity_squares(entity) }.flatten(1)

      base_map.transpose.each_with_index.map do |row, row_index|
        row.each_with_index.map do |c, col_index|
          display = render_position(c, col_index, row_index, path: path, entity: entity, line_of_sight: line_of_sight,
                                                             update_on_drop: update_on_drop, acrobatics_checks: acrobatics_checks,
                                                             athletics_checks: athletics_checks)

          display = display.colorize(background: :red) if highlight_positions.include?([col_index, row_index])

          if select_pos && select_pos == [col_index, row_index]
            display.colorize(background: :white)
          else
            display
          end
        end.join
      end.join("\n") + "\n"
    end

    private

    def render_light(pos_x, pos_y)
      intensity = @map.light_at(pos_x, pos_y)
      if intensity >= 1.0
        :light_black
      elsif intensity >= 0.5
        :black
      else
        :default
      end
    end

    def object_token(pos_x, pos_y)
      object_meta = @map.object_at(pos_x, pos_y)
      return nil unless object_meta
      m_x, m_y = @map.interactable_objects[object_meta]
      color = (object_meta.color.presence || DEFAULT_TOKEN_COLOR).to_sym

      return nil unless object_meta.token

      if object_meta.token.is_a?(Array)
        object_meta.token[pos_y - m_y][pos_x - m_x].colorize(color)
      else
        object_meta.token.colorize(color)
      end
    end

    def npc_token(pos_x, pos_y)
      entity = tokens[pos_x][pos_y]
      color = (entity[:entity]&.color.presence || DEFAULT_TOKEN_COLOR).to_sym
      token(entity, pos_x, pos_y).colorize(color)
    end

    def render_position(c, col_index, row_index, path: [], entity: nil, line_of_sight: nil, update_on_drop: true, acrobatics_checks: [],
                        athletics_checks: [])
      background_color = render_light(col_index, row_index)
      default_ground = "\u00B7".encode('utf-8').colorize(color: DEFAULT_TOKEN_COLOR, background: background_color)
      c = case c
          when '.', '?'
            default_ground
          else
            object_token(col_index, row_index)&.colorize(background: background_color) || default_ground
          end

      if !path.empty? && path[0] != [col_index, row_index]
        if path.include?([col_index, row_index])
          path_char = '+'
          path_color = entity && map.jump_required?(entity, col_index, row_index) ? :red : :blue
          path_char = "\u2713" if athletics_checks.include?([col_index,
                                                             row_index]) || acrobatics_checks.include?([col_index,
                                                                                                        row_index])
          return path_char.colorize(color: path_color, background: background_color)
        end
        return ' '.colorize(background: :black) if line_of_sight && !location_is_visible?(update_on_drop, col_index, row_index,
                                                                                          path)
      else
        has_line_of_sight = if line_of_sight.is_a?(Array)
                              line_of_sight.detect { |l| @map.can_see_square?(l, col_index, row_index) }
                            elsif line_of_sight
                              @map.can_see_square?(line_of_sight, col_index, row_index)
                            end
        return ' '.colorize(background: :black) if line_of_sight && !has_line_of_sight
      end

      # render map layer
      token = if tokens[col_index][row_index]&.fetch(:entity)&.dead?
                '`'.colorize(color: DEFAULT_TOKEN_COLOR)
              elsif tokens[col_index][row_index]
                if any_line_of_sight?(line_of_sight, tokens[col_index][row_index][:entity])
                  npc_token(col_index,
                            row_index)
                end
              end

      (token&.colorize(background: background_color) || c)
    end

    def location_is_visible?(update_on_drop, pos_x, pos_y, path)
      return @map.line_of_sight?(path.last[0], path.last[1], col_index, row_index, nil, false) unless update_on_drop

      @map.line_of_sight?(path.last[0], path.last[1], pos_x, pos_y,
                          1, false) || @map.line_of_sight?(path.first[0], path.first[1], pos_x, pos_y, nil, false)
    end

    def any_line_of_sight?(line_of_sight, entity)
      return true if @battle.nil?

      if line_of_sight.is_a?(Array)
        line_of_sight.detect do |l|
          @battle.can_see?(l,
                           entity)
        end
      else
        @battle.can_see?(line_of_sight,
                         entity)
      end
    end

    def base_map
      @map.base_map
    end

    # Returns the character to use as token for a square
    # @param entity [Natural20::Entity]
    # @param pos_x [Integer]
    # @param pos_y [Integer]
    # @return [String]
    def token(entity, pos_x, pos_y)
      if entity[:entity].token
        m_x, m_y = @map.entities[entity[:entity]]
        entity[:entity].token[pos_y - m_y][pos_x - m_x]
      else
        @map.tokens[pos_x][pos_y][:token]
      end
    end

    def tokens
      @map.tokens
    end
  end
end
