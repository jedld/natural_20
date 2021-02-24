# typed: false
module Natural20
  class BattleMap
    include Natural20::Cover
    include Natural20::MovementHelper

    attr_reader :properties, :base_map, :spawn_points, :tokens, :entities, :size, :interactable_objects, :session,
                :unaware_npcs, :size, :area_triggers, :feet_per_grid

    # @param session [Natural20::Session] The current game session
    # @param map_file [String] Path to map file
    def initialize(session, map_file)
      @session = session
      @map_file = map_file
      @spawn_points = {}
      @entities = {}
      @area_triggers = {}
      @interactable_objects = {}
      @unaware_npcs = []

      @properties = YAML.load_file(File.join(session.root_path, "#{map_file}.yml")).deep_symbolize_keys!

      @feet_per_grid = @properties[:grid_size] || 5

      # terrain layer

      base = @properties.dig(:map, :base)

      @size = [base.first.size, base.size]

      @base_map = @size[0].times.map do
        @size[1].times.map do
          nil
        end
      end

      @properties.dig(:map, :base).each_with_index.map do |lines, cur_y|
        lines.each_char.map.each_with_index do |c, cur_x|
          @base_map[cur_x][cur_y] = c
        end
      end

      # terrain layer 2
      @base_map_1 = @size[0].times.map do
        @size[1].times.map { nil }
      end

      unless @properties.dig(:map, :base_1).blank?
        @properties.dig(:map, :base_1).each_with_index do |lines, cur_y|
          lines.each_char.map.each_with_index do |c, cur_x|
            @base_map_1[cur_x][cur_y] = (c == '.' ? nil : c)
          end
        end
      end

      # meta layer
      if @properties.dig(:map, :meta)
        @meta_map = @size[0].times.map do
          @size[1].times.map { nil }
        end

        @properties.dig(:map, :meta).each_with_index do |lines, cur_y|
          lines.each_char.map.each_with_index do |c, cur_x|
            @meta_map[cur_x][cur_y] = c
          end
        end
      end

      @legend = @properties[:legend] || {}

      @tokens = @size[0].times.map do
        @size[1].times.map { nil }
      end

      @area_notes = @size[0].times.map do
        @size[1].times.map { nil }
      end

      @objects = @size[0].times.map do
        @size[1].times.map do
          []
        end
      end

      @properties[:notes]&.each_with_index do |note, index|
        note_object = OpenStruct.new(note.merge(note_id: note[:id] || index))
        note_positions = case note_object.type
                         when 'point'
                           note[:positions]
                         when 'rectangle'
                           note[:positions].map do |position|
                             left_x, left_y, right_x, right_y = position

                             (left_x..right_x).map do |pos_x|
                               (left_y..right_y).map do |pos_y|
                                 [pos_x, pos_y]
                               end
                             end
                           end.flatten(2).uniq
                         else
                           raise "invalid note type #{note_object.type}"
                         end

        note_positions.each do |position|
          pos_x, pos_y = position
          @area_notes[pos_x][pos_y] ||= []
          @area_notes[pos_x][pos_y] << note_object unless @area_notes[pos_x][pos_y].include?(note_object)
        end
      end

      @triggers = (@properties[:triggers] || {}).deep_symbolize_keys

      @light_builder = Natural20::StaticLightBuilder.new(self)

      setup_objects
      setup_npcs
      compute_lights # compute static lights
    end

    def activate_map_triggers(trigger_type, source, opt = {})
      return unless @triggers.key?(trigger_type.to_sym)

      @triggers[trigger_type.to_sym].each do |trigger|
        next if trigger[:if] && !source&.eval_if(trigger[:if], opt)

        case trigger[:type]
        when 'message'
          opt[:ui_controller]&.show_message(trigger[:content])
        when 'battle_end'
          return :battle_end
        else
          raise "unknown trigger type #{trigger[:type]}"
        end
      end
    end

    def wall?(pos_x, pos_y)
      return true if pos_x.negative? || pos_y.negative?
      return true if pos_x >= size[0] || pos_y >= size[1]

      return true if object_at(pos_x, pos_y)&.wall?

      false
    end

    # Get object at map location
    # @param pos_x [Integer]
    # @param pos_y [Integer]
    # @param reveal_concealed [Boolean]
    # @return [ItemLibrary::Object]
    def object_at(pos_x, pos_y, reveal_concealed: false)
      @objects[pos_x][pos_y]&.detect { |o| reveal_concealed || !o.concealed? }
    end

    # Get object at map location
    # @param pos_x [Integer]
    # @param pos_y [Integer]
    # @return [Array<ItemLibrary::Object>]
    def objects_at(pos_x, pos_y)
      @objects[pos_x][pos_y]
    end

    # Lists interactable objects near an entity
    # @param entity [Entity]
    # @param battle [Natural20::Battle]
    # @return [Array]
    def objects_near(entity, battle = nil)
      target_squares = entity.melee_squares(self)
      target_squares += battle.map.entity_squares(entity) if battle&.map
      objects = []

      available_objects = target_squares.map do |square|
        objects_at(*square)
      end.flatten.compact

      available_objects.each do |object|
        objects << object unless object.available_interactions(entity, battle).empty?
      end

      @entities.each do |object, position|
        next if object == entity

        objects << object if !object.available_interactions(entity, battle).empty? && target_squares.include?(position)
      end
      objects
    end

    def items_on_the_ground(entity)
      target_squares = entity.melee_squares(self)
      target_squares += entity_squares(entity)

      available_objects = target_squares.map do |square|
        objects_at(*square)
      end.flatten.compact

      ground_objects = available_objects.select { |obj| obj.is_a?(ItemLibrary::Ground) }
      ground_objects.map do |obj|
        items = obj.inventory.select { |o| o.qty.positive? }
        next if items.empty?

        [obj, items]
      end.compact
    end

    def ground_at(pos_x, pos_y)
      available_objects = objects_at(pos_x, pos_y).compact
      available_objects.detect { |obj| obj.is_a?(ItemLibrary::Ground) }
    end

    # Place token here if it is not already present on the board
    # @param pos_x [Integer]
    # @param pos_y [Integer]
    # @param entity [Natural20::Entity]
    # @param token [String]
    # @param battle [Natural20::Battle]
    def place(pos_x, pos_y, entity, token = nil, battle = nil)
      raise 'entity param is required' if entity.nil?

      entity_data = { entity: entity, token: token || entity.name&.first }
      @tokens[pos_x][pos_y] = entity_data
      @entities[entity] = [pos_x, pos_y]

      source_token_size = if requires_squeeze?(entity, pos_x, pos_y, self, battle)
                            entity.squeezed!
                            [entity.token_size - 1, 1].max
                          else
                            entity.token_size
                          end

      (0...source_token_size).each do |ofs_x|
        (0...source_token_size).each do |ofs_y|
          @tokens[pos_x + ofs_x][pos_y + ofs_y] = entity_data
        end
      end
    end

    def place_at_spawn_point(position, entity, token = nil, battle = nil)
      unless @spawn_points.key?(position.to_s)
        raise "unknown spawn position #{position}. should be any of #{@spawn_points.keys.join(',')}"
      end

      pos_x, pos_y = @spawn_points[position.to_s][:location]
      place(pos_x, pos_y, entity, token, battle)
      EventManager.logger.debug "place #{entity.name} at #{pos_x}, #{pos_y}"
    end

    # Computes the distance between two entities
    # @param entity1 [Natural20::Entity]
    # @param entity2 [Natural20::Entity]
    # @result [Integer]
    def distance(entity1, entity2, entity_1_pos: nil, entity_2_pos: nil)
      raise 'entity 1 param cannot be nil' if entity1.nil?
      raise 'entity 2 param cannot be nil' if entity2.nil?

      # entity 1 squares
      entity_1_sq = entity_1_pos ? entity_squares_at_pos(entity1, *entity_1_pos) : entity_squares(entity1)
      entity_2_sq = entity_2_pos ? entity_squares_at_pos(entity2, *entity_2_pos) : entity_squares(entity2)

      entity_1_sq.map do |ent1_pos|
        entity_2_sq.map do |ent2_pos|
          pos1_x, pos1_y = ent1_pos
          pos2_x, pos2_y = ent2_pos
          Math.sqrt((pos1_x - pos2_x)**2 + (pos1_y - pos2_y)**2).floor
        end
      end.flatten.min
    end

    # Returns the line distance between an entity and a location
    # @param entity [Natural20::Entity]
    # @param pos2_x [Integer]
    # @param pos2_y [Integer]
    # @result [Integer]
    def line_distance(entity1, pos2_x, pos2_y, entity_1_pos: nil)
      entity_1_sq = entity_1_pos ? entity_squares_at_pos(entity1, *entity_1_pos) : entity_squares(entity1)

      entity_1_sq.map do |ent1_pos|
        pos1_x, pos1_y = ent1_pos
        Math.sqrt((pos1_x - pos2_x)**2 + (pos1_y - pos2_y)**2)
      end.flatten.min
    end

    # Get all the location of the squares occupied by said entity (e.g. for large, huge creatures)
    # @param entity [Natural20::Entity]
    # @return [Array]
    def entity_squares(entity, squeeze = false)
      raise 'invalid entity' unless entity

      pos1_x, pos1_y = entity_or_object_pos(entity)
      entity_1_squares = []
      token_size = if squeeze
                     [entity.token_size - 1, 1].max
                   else
                     entity.token_size
                   end
      (0...token_size).each do |ofs_x|
        (0...token_size).each do |ofs_y|
          next if (pos1_x + ofs_x >= size[0]) || (pos1_y + ofs_y >= size[1])

          entity_1_squares << [pos1_x + ofs_x, pos1_y + ofs_y]
        end
      end
      entity_1_squares
    end

    # Get all the location of the squares occupied by said entity (e.g. for large, huge creatures)
    # and use specified entity location instead of current location on the map
    # @param entity [Natural20::Entity]
    # @param pos1_x [Integer]
    # @param pos1_y [Integer]
    # @return [Array]
    def entity_squares_at_pos(entity, pos1_x, pos1_y, squeeze = false)
      entity_1_squares = []
      token_size = if squeeze
                     [entity.token_size - 1, 1].max
                   else
                     entity.token_size
                   end
      (0...token_size).each do |ofs_x|
        (0...token_size).each do |ofs_y|
          next if (pos1_x + ofs_x >= size[0]) || (pos1_y + ofs_y >= size[1])

          entity_1_squares << [pos1_x + ofs_x, pos1_y + ofs_y]
        end
      end
      entity_1_squares
    end

    # Natural20::Entity to look around
    # @param entity [Natural20::Entity] The entity to look around his line of sight
    # @return [Hash] entities in line of sight
    def look(entity, distance = nil)
      @entities.map do |k, v|
        next if k == entity

        pos1_x, pos1_y = v
        next unless can_see?(entity, k, distance: distance)

        [k, [pos1_x, pos1_y]]
      end.compact.to_h
    end

    # Compute if entity is in line of sight
    # @param entity [Natural20::Entity]
    # @param pos2_x [Integer]
    # @param pos2_y [Integer]
    # @param distance [Integer]
    # @return [TrueClass, FalseClass]
    def line_of_sight_for?(entity, pos2_x, pos2_y, distance = nil)
      raise 'cannot find entity' if @entities[entity].nil?

      pos1_x, pos1_y = @entities[entity]
      line_of_sight?(pos1_x, pos1_y, pos2_x, pos2_y, distance: distance)
    end

    # Test to see if an entity can see a square
    # @param entity [Natural20::Entity]
    # @param pos2_x [Integer]
    # @param pos2_y [Integer]
    # @param allow_dark_vision [Boolean] Allow darkvision
    # @return [Boolean]
    def can_see_square?(entity, pos2_x, pos2_y, allow_dark_vision: true)
      has_line_of_sight = false
      max_illumniation = 0.0
      sighting_distance = nil

      entity_1_squares = entity_squares(entity)
      entity_1_squares.each do |pos1|
        pos1_x, pos1_y = pos1
        return true if [pos1_x, pos1_y] == [pos2_x, pos2_y]
        next unless line_of_sight?(pos1_x, pos1_y, pos2_x, pos2_y, inclusive: false)

        location_illumnination = light_at(pos2_x, pos2_y)
        max_illumniation = [location_illumnination, max_illumniation].max
        sighting_distance = Math.sqrt((pos1_x - pos2_x)**2 + (pos1_y - pos2_y)**2).floor
        has_line_of_sight = true
      end

      if has_line_of_sight && max_illumniation < 0.5
        return allow_dark_vision && entity.darkvision?(sighting_distance * @feet_per_grid)
      end

      has_line_of_sight
    end

    # Checks if an entity can see another
    # @param entity [Natural20::Entity] entity looking
    # @param entity2 [Natural20::Entity] entity being looked at
    # @param distance [Integer]
    # @param entity_2_pos [Array] position override for entity2
    # @param allow_dark_vision [Boolean] Allow darkvision
    # @return [Boolean]
    def can_see?(entity, entity2, distance: nil, entity_1_pos: nil, entity_2_pos: nil, allow_dark_vision: true, active_perception: 0, active_perception_disadvantage: 0)
      raise 'invalid entity passed' if @entities[entity].nil? && @interactable_objects[entity].nil?

      entity_1_squares = entity_1_pos ? entity_squares_at_pos(entity, *entity_1_pos) : entity_squares(entity)
      entity_2_squares = entity_2_pos ? entity_squares_at_pos(entity2, *entity_2_pos) : entity_squares(entity2)

      has_line_of_sight = false
      max_illumniation = 0.0
      sighting_distance = nil

      entity_1_squares.each do |pos1|
        entity_2_squares.each do |pos2|
          pos1_x, pos1_y = pos1
          pos2_x, pos2_y = pos2
          next if pos1_x >= size[0] || pos1_x.negative? || pos1_y >= size[1] || pos1_y.negative?
          next if pos2_x >= size[0] || pos2_x.negative? || pos2_y >= size[1] || pos2_y.negative?
          next unless line_of_sight?(pos1_x, pos1_y, pos2_x, pos2_y, distance: distance)

          location_illumnination = light_at(pos2_x, pos2_y)
          max_illumniation = [location_illumnination, max_illumniation].max
          sighting_distance = Math.sqrt((pos1_x - pos2_x)**2 + (pos1_y - pos2_y)**2).floor
          has_line_of_sight = true
        end
      end

      if has_line_of_sight && max_illumniation < 0.5
        return allow_dark_vision && entity.darkvision?(sighting_distance * @feet_per_grid)
      end

      has_line_of_sight
    end

    def light_at(pos_x, pos_y)
      if @light_map
        return @light_map[pos_x][pos_y] if @light_map[pos_x][pos_y] >= 1.0

        @light_map[pos_x][pos_y] + @light_builder.light_at(pos_x, pos_y)
      else
        @light_builder.light_at(pos_x, pos_y)
      end
    end

    def position_of(entity)
      entity.is_a?(ItemLibrary::Object) ? interactable_objects[entity] : @entities[entity]
    end

    # Get entity at map location
    # @param pos_x [Integer]
    # @param pos_y [Integer]
    # @return [Natural20::Entity]
    def entity_at(pos_x, pos_y)
      entity_data = @tokens[pos_x][pos_y]
      return nil if entity_data.nil?

      entity_data[:entity]
    end

    # Get entity or object at map location
    # @param pos_x [Integer]
    # @param pos_y [Integer]
    # @param reveal_concealed [Boolean] Included concealed objects
    # @return [Array<Nautral20::Entity>]
    def thing_at(pos_x, pos_y, reveal_concealed: false)
      things = []
      things << entity_at(pos_x, pos_y)
      things << object_at(pos_x, pos_y, reveal_concealed: reveal_concealed)
      things.compact
    end

    # Moves an entity to a specified location on the board
    # @param entity [Natural20::Entity]
    # @param pos_x [Integer]
    # @param pos_y [Integer]
    # @param battle [Natural20::Battle]
    def move_to!(entity, pos_x, pos_y, battle)
      cur_x, cur_y = @entities[entity]

      entity_data = @tokens[cur_x][cur_y]

      source_token_size = if requires_squeeze?(entity, cur_x, cur_y, self, battle)
                            [entity.token_size - 1, 1].max
                          else
                            entity.token_size
                          end

      destination_token_size = if requires_squeeze?(entity, pos_x, pos_y, self, battle)
                                 entity.squeezed!
                                 [entity.token_size - 1, 1].max
                               else
                                 entity.unsqueeze
                                 entity.token_size
                               end

      (0...source_token_size).each do |ofs_x|
        (0...source_token_size).each do |ofs_y|
          @tokens[cur_x + ofs_x][cur_y + ofs_y] = nil
        end
      end

      (0...destination_token_size).each do |ofs_x|
        (0...destination_token_size).each do |ofs_y|
          @tokens[pos_x + ofs_x][pos_y + ofs_y] = entity_data
        end
      end

      @entities[entity] = [pos_x, pos_y]
    end

    def valid_position?(pos_x, pos_y)
      return false if pos_x >= @base_map.size || pos_x.negative? || pos_y >= @base_map[0].size || pos_y.negative?

      return false if @base_map[pos_x][pos_y] == '#'
      return false unless @tokens[pos_x][pos_y].nil?

      true
    end

    # @param entity [Natural20::Entity]
    # @param path [Array]
    # @param battle [Natural20::Battle]
    # @param manual_jump [Array]
    # @return [Natural20::MovementHelper::Movement]
    def movement_cost(entity, path, battle = nil, manual_jump = [])
      return Natural20::MovementHelper::Movement.empty if path.empty?

      budget = entity.available_movement(battle) / @feet_per_grid
      compute_actual_moves(entity, path, self, battle, budget, test_placement: false,
                                                               manual_jump: manual_jump)
    end

    # Describes if terrain is passable or not
    # @param entity [Natural20::Entity]
    # @param pos_x [Integer]
    # @param pos_y [Integer]
    # @param battle [Natural20::Battle]
    # @param allow_squeeze [Boolean] Allow entity to squeeze inside a space (PHB )
    # @return [Boolean]
    def passable?(entity, pos_x, pos_y, battle = nil, allow_squeeze = true)
      effective_token_size = if allow_squeeze
                               [entity.token_size - 1, 1].max
                             else
                               entity.token_size
                             end

      (0...effective_token_size).each do |ofs_x|
        (0...effective_token_size).each do |ofs_y|
          relative_x = pos_x + ofs_x
          relative_y = pos_y + ofs_y

          return false if relative_x >= @size[0]
          return false if relative_y >= @size[1]

          return false if @base_map[relative_x][relative_y] == '#'
          return false if object_at(relative_x, relative_y) && !object_at(relative_x, relative_y).passable?

          next unless battle && @tokens[relative_x][relative_y]

          location_entity = @tokens[relative_x][relative_y][:entity]

          next if @tokens[relative_x][relative_y][:entity] == entity
          next unless battle.opposing?(location_entity, entity)
          next if location_entity.dead? || location_entity.unconscious?
          if entity.class_feature?('halfling_nimbleness') && (location_entity.size_identifier - entity.size_identifier) >= 1
            next
          end
          if battle.opposing?(location_entity,
                              entity) && (location_entity.size_identifier - entity.size_identifier).abs < 2
            return false
          end
        end
      end

      true
    end

    def squares_in_path(pos1_x, pos1_y, pos2_x, pos2_y, distance: nil, inclusive: true)
      if [pos1_x, pos1_y] == [pos2_x, pos2_y]
        return inclusive ? [[pos1_x, pos1_y]] : []
      end

      arrs = []
      if pos2_x == pos1_x
        scanner = pos2_y > pos1_y ? (pos1_y...pos2_y) : (pos2_y...pos1_y)

        scanner.each_with_index do |y, index|
          break if !distance.nil? && index >= distance
          next if !inclusive && ((y == pos1_y) || (y == pos2_y))

          arrs << [pos1_x, y]
        end
      else
        m = (pos2_y - pos1_y).to_f / (pos2_x - pos1_x)
        scanner = pos2_x > pos1_x ? (pos1_x...pos2_x) : (pos2_x...pos1_x)
        if m.zero?
          scanner.each_with_index do |x, index|
            break if !distance.nil? && index >= distance
            next if !inclusive && ((x == pos1_x) || (x == pos2_x))

            arrs << [x, pos2_y]
          end
        else
          b = pos1_y - m * pos1_x
          step = m.abs > 1 ? 1 / m.abs : m.abs

          scanner.step(step).each_with_index do |x, index|
            y = (m * x + b).round

            break if !distance.nil? && index >= distance
            next if !inclusive && ((x.round == pos1_x && y == pos1_y) || (x.round == pos2_x && y == pos2_y))

            arrs << [x.round, y]
          end
        end
      end

      arrs.uniq
    end

    # Determines if it is possible to place a token in this location
    # @param entity [Natural20::Entity]
    # @param pos_x [Integer]
    # @param pos_y [Integer]
    # @param battle [Natural20::Battle]
    # @return [Boolean]
    def placeable?(entity, pos_x, pos_y, battle = nil, squeeze = true)
      return false unless passable?(entity, pos_x, pos_y, battle, squeeze)

      entity_squares_at_pos(entity, pos_x, pos_y, squeeze).each do |pos|
        p_x, p_y = pos
        next if @tokens[p_x][p_y] && @tokens[p_x][p_y][:entity] == entity
        return false if @tokens[p_x][p_y] && !@tokens[p_x][p_y][:entity].dead?
        return false if object_at(p_x, p_y) && !object_at(p_x, p_y)&.passable?
        return false if object_at(p_x, p_y) && !object_at(p_x, p_y)&.placeable?
      end

      true
    end

    # Determines if terrain is a difficult terrain
    # @param entity [Natural20::Entity]
    # @param pos_x [Integer]
    # @param pos_y [Integer]
    # @param battle [Natural20::Battle]
    # @return [Boolean] Returns if difficult terrain or not
    def difficult_terrain?(entity, pos_x, pos_y, _battle = nil)
      entity_squares_at_pos(entity, pos_x, pos_y).each do |pos|
        r_x, r_y = pos
        next if @tokens[r_x][r_y] && @tokens[r_x][r_y][:entity] == entity
        return true if @tokens[r_x][r_y] && !@tokens[r_x][r_y][:entity].dead?
        return true if object_at(r_x, r_y) && object_at(r_x, r_y)&.movement_cost > 1
      end

      false
    end

    def jump_required?(entity, pos_x, pos_y)
      entity_squares_at_pos(entity, pos_x, pos_y).each do |pos|
        r_x, r_y = pos
        next if @tokens[r_x][r_y] && @tokens[r_x][r_y][:entity] == entity
        return true if object_at(r_x, r_y) && object_at(r_x, r_y)&.jump_required? && !entity.flying?
      end

      false
    end

    # check if this interrupts line of sight (not necessarily movement)
    def opaque?(pos_x, pos_y)
      case (@base_map[pos_x][pos_y])
      when '#'
        true
      when '.'
        false
      else
        object_at(pos_x, pos_y)&.opaque?
      end
    end

    # Computes one of sight between two points
    # @param pos1_x [Integer]
    # @param pos1_y [Integer]
    # @param pos2_x [Integer]
    # @param pos2_y [Integer]
    # @param distance [Integer]
    # @return [Array<Array<Integer,Integer>>] Cover characteristics if there is LOS
    def line_of_sight?(pos1_x, pos1_y, pos2_x, pos2_y, distance: nil, inclusive: false, entity: false)
      squares = squares_in_path(pos1_x, pos1_y, pos2_x, pos2_y, inclusive: inclusive)

      squares.each_with_index.map do |s, index|
        return nil if distance && index == (distance - 1)
        return nil if opaque?(*s)
        return nil if cover_at(*s) == :total

        [cover_at(*s, entity), s]
      end
    end

    # Computes one of sight between two points
    # @param pos1_x [Integer]
    # @param pos1_y [Integer]
    # @param pos2_x [Integer]
    # @param pos2_y [Integer]
    # @param distance [Integer]
    # @return [Array<Array<Integer,Integer>>] Cover characteristics if there is LOS
    def light_in_sight?(pos1_x, pos1_y, pos2_x, pos2_y, min_distance: nil, distance: nil, inclusive: false, entity: false)
      squares = squares_in_path(pos1_x, pos1_y, pos2_x, pos2_y, inclusive: inclusive)
      min_distance_reached = true

      squares.each_with_index.each do |s, index|
        min_distance_reached = false if min_distance && index >= (min_distance - 1)
        return [false, false] if distance && index >= (distance - 1)
        return [false, false] if opaque?(*s)
        return [false, false] if cover_at(*s) == :total
      end

      [min_distance_reached, true]
    end

    # @param pos_x [Integer]
    # @param pos_y [Integer]
    # @param entity [Boolean] inlcude entities
    def cover_at(pos_x, pos_y, entity = false)
      return :half if object_at(pos_x, pos_y)&.half_cover?
      return :three_quarter if object_at(pos_x, pos_y)&.three_quarter_cover?
      return :total if object_at(pos_x, pos_y)&.total_cover?

      return entity_at(pos_x, pos_y).size_identifier if entity && entity_at(pos_x, pos_y)

      :none
    end

    # highlights objects of interest if enabled on object
    # @param source [Natural20::Entity] entity that is observing
    # @param perception_check [Integer] Perception value
    # @returns [Hash] objects of interest with notes
    def highlight(source, perception_check)
      (@entities.keys + interactable_objects.keys).map do |entity|
        next if source == entity
        next unless can_see?(source, entity)

        perception_key = "#{source.entity_uid}_#{entity.entity_uid}"
        perception_check = @session.load_state(:perception).fetch(perception_key, perception_check)
        @session.save_state(:perception, { perception_key => perception_check })
        highlighted_notes = entity.try(:list_notes, source, perception_check, highlight: true) || []

        next if highlighted_notes.empty?

        [entity, highlighted_notes]
      end.compact.to_h
    end

    # Reads perception related notes on an entity
    # @param entity [Object] The target to percive on
    # @param source [Natural20::Entity] Entity perceiving
    # @param perception_check [Integer] Perception roll of source
    # @return [Array] Array of notes
    def perception_on(entity, source, perception_check)
      perception_key = "#{source.entity_uid}_#{entity.entity_uid}"
      perception_check = @session.load_state(:perception).fetch(perception_key, perception_check)
      @session.save_state(:perception, { perception_key => perception_check })
      entity.try(:list_notes, source, perception_check) || []
    end

    # Reads perception related notes on an area
    # @param pos_x [Integer]
    # @param pos_y [Integer]
    # @param source [Natural20::Entity]
    # @param perception_check [Integer] Perception roll of source
    # @return [Array] Array of notes
    def perception_on_area(pos_x, pos_y, source, perception_check)
      notes = @area_notes[pos_x][pos_y] || []

      notes.map do |note_object|
        note_object.notes.each_with_index.map do |note, index|
          perception_key = "#{source.entity_uid}_#{note_object.note_id}_#{index}"
          perception_check = @session.load_state(:perception).fetch(perception_key, perception_check)
          @session.save_state(:perception, { perception_key => perception_check })
          next if note[:perception_dc] && perception_check <= note[:perception_dc]

          if note[:perception_dc] && note[:perception_dc] != 0
            t('perception.passed', note: note[:note])
          else
            note[:note]
          end
        end
      end.flatten.compact
    end

    def area_trigger!(entity, position, is_flying)
      trigger_results = @area_triggers.map do |k, _prop|
        next if k.dead?

        k.area_trigger_handler(entity, position, is_flying)
      end.flatten.compact

      trigger_results.uniq
    end

    # @param thing [Natural20::Entity]
    # @return [Array<Integer,Integer>]
    def entity_or_object_pos(thing)
      thing.is_a?(ItemLibrary::Object) ? @interactable_objects[thing] : @entities[thing]
    end

    # Places an object onto the map
    # @param object_info [Hash]
    # @param pos_x [Integer]
    # @param pos_y [Integer]
    # @param object_meta [Hash]
    # @return [ItemLibrary::Object]
    def place_object(object_info, pos_x, pos_y, object_meta = {})
      return if object_info.nil?

      obj = if object_info.is_a?(ItemLibrary::Object)
              object_info
            elsif object_info[:item_class]
              item_klass = object_info[:item_class].constantize

              item_obj = item_klass.new(self, object_info.merge(object_meta))
              @area_triggers[item_obj] = {} if item_klass.included_modules.include?(ItemLibrary::AreaTrigger)

              item_obj
            else
              ItemLibrary::Object.new(self, object_meta.merge(object_info))
            end

      @interactable_objects[obj] = [pos_x, pos_y]

      if obj.token.is_a?(Array)
        obj.token.each_with_index do |line, y|
          line.each_char.map.to_a.each_with_index do |t, x|
            next if t == '.' # ignore mask

            @objects[pos_x + x][pos_y + y] << obj
          end
        end
      else
        @objects[pos_x][pos_y] << obj
      end

      obj
    end

    # @param entity [Natural20::Battle]
    # @param pos_x [Integer]
    # @param pos_y [Integer]
    # @param group [Symbol]
    def add(entity, pos_x, pos_y, group: :b)
      @unaware_npcs << { group: group&.to_sym || :b, entity: entity }
      @entities[entity] = [pos_x, pos_y]
      place(pos_x, pos_y, entity, nil)
    end

    protected

    def compute_lights
      @light_map = @light_builder.build_map
    end

    def setup_objects
      @size[0].times do |pos_x|
        @size[1].times do |pos_y|
          tokens = [@base_map_1[pos_x][pos_y], @base_map[pos_x][pos_y]].compact
          tokens.map do |token|
            case token
            when '#'
              object_info = @session.load_object('stone_wall')
              obj = ItemLibrary::StoneWall.new(self, object_info)
              @interactable_objects[obj] = [pos_x, pos_y]
              place_object(obj, pos_x, pos_y)
            when '?'
              nil
            when '.'
              place_object(ItemLibrary::Ground.new(self, name: 'ground'), pos_x, pos_y)
            else
              object_meta = @legend[token.to_sym]
              raise "unknown object token #{token}" if object_meta.nil?
              next nil if object_meta[:type] == 'mask' # this is a mask terrain so ignore

              object_info = @session.load_object(object_meta[:type])
              place_object(object_info, pos_x, pos_y, object_meta)
            end
          end
        end
      end
    end

    def setup_npcs
      @meta_map&.each_with_index do |meta_row, column_index|
        meta_row.each_with_index do |token, row_index|
          token_type = @legend.dig(token.to_sym, :type)

          case token_type
          when 'npc'
            npc_meta = @legend[token.to_sym]
            raise 'npc type requires sub_type as well' unless npc_meta[:sub_type]

            entity = session.npc(npc_meta[:sub_type].to_sym, name: npc_meta[:name], overrides: npc_meta[:overrides],
                                                             rand_life: true)

            add(entity, column_index, row_index, group: npc_meta[:group])
          when 'spawn_point'
            @spawn_points[@legend.dig(token.to_sym, :name)] = {
              location: [column_index, row_index]
            }
          end
        end
      end
    end
  end
end
