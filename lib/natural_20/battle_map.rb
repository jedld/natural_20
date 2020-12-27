class BattleMap
  attr_reader :base_map, :spawn_points, :size, :interactable_objects, :unaware_npcs

  def initialize(session, map_file)
    @session = session
    @map_file = map_file
    @spawn_points = {}
    @entities = {}
    @interactable_objects = {}
    @unaware_npcs = []

    @properties = YAML.load_file(File.join(File.dirname(__FILE__), '..', "#{map_file}.yml")).deep_symbolize_keys!

    # terrain layer
    @base_map = @properties.dig(:map, :base).map do |lines|
      lines.each_char.map.to_a
    end.transpose

    # meta layer
    if @properties.dig(:map, :meta)
      @meta_map = @properties.dig(:map, :meta).map do |lines|
        lines.each_char.map.to_a
      end.transpose
    end

    @legend = @properties[:legend] || {}

    @size = [@base_map.size, @base_map.first.size]
    @tokens = @size[0].times.map do
      @size[1].times.map { nil }
    end

    @objects = @size[0].times.map do |pos_x|
      @size[1].times.map do |pos_y|
        token = @base_map[pos_x][pos_y]
        case token
        when '#'
          nil
        when '.'
          nil
        else
          object_meta = @legend[token.to_sym]
          raise "unknown object token #{token}" if object_meta.nil?

          object_info = Session.load_object(object_meta[:type])
          obj = if object_info[:item_class]
                  object_info[:item_class].constantize.new(self, object_meta.merge(object_info))
                else
                  ItemLibrary::Object.new(self, object_meta.merge(object_info))
                end

          @interactable_objects[obj] = [pos_x, pos_y]
          obj
        end
      end
    end

    if @meta_map
      @meta_map.each_with_index do |meta_row, column_index|
        meta_row.each_with_index do |token, row_index|
          token_type = @legend.dig(token.to_sym, :type)
          case token_type
          when 'npc'
            npc_meta = @legend.dig(token.to_sym)
            entity = Npc.new(npc_meta[:sub_type].to_sym, name: npc_meta[:name], overrides: npc_meta[:overrides])
            @unaware_npcs << entity
            place(column_index, row_index, entity)
          when 'spawn_point'
            @spawn_points[@legend.dig(token.to_sym, :name)] = {
              location: [column_index, row_index]
            }
          end
        end
      end
    end
  end

  attr_reader :size

  def wall?(pos_x, pos_y)
    return true if pos_x.negative? || pos_y.negative?
    return true if pos_x >= size[0] || pos_y >= size[1]

    return true if base_map[pos_x][pos_y] == '#'

    false
  end

  # Get object at map location
  # @param pos_x [Integer]
  # @param pos_y [Integer]
  def object_at(pos_x, pos_y)
    @objects[pos_x][pos_y]
  end

  def objects_near(entity, battle = nil)
    target_squares = entity.melee_squares(self, @entities[entity])
    objects = []
    @interactable_objects.each do |object, position|
      objects << object if !object.available_actions(entity, battle).empty? && target_squares.include?(position)
    end
    objects
  end

  def place(pos_x, pos_y, entity, token = nil)
    raise 'entity param is required' if entity.nil?

    entity_data = { entity: entity, token: token || entity.name&.first }
    @tokens[pos_x][pos_y] = entity_data
    @entities[entity] = [pos_x, pos_y]

    (0...entity.token_size).each do |ofs_x|
      (0...entity.token_size).each do |ofs_y|
        @tokens[pos_x + ofs_x][pos_y + ofs_y] = entity_data
      end
    end
  end

  def place_at_spawn_point(position, entity, token = nil)
    unless @spawn_points.key?(position.to_s)
      raise "unknown spawn position #{position}. should be any of #{@spawn_points.keys.join(',')}"
    end

    pos_x, pos_y = @spawn_points[position.to_s][:location]
    place(pos_x, pos_y, entity, token)
    puts "place #{entity.name} at #{pos_x}, #{pos_y}"
  end

  # Computes the distance between two entities
  # @param entity1 [Entity]
  # @param entity2 [Entity]
  # @result [Integer]
  def distance(entity1, entity2)
    raise 'entity 1 param cannot be nil' if entity1.nil?
    raise 'entity 2 param cannot be nil' if entity2.nil?

    # entity 1 squares
    entity_1_sq = entity_squares(entity1)
    entity_2_sq = entity_squares(entity2)

    entity_1_sq.map do |ent1_pos|
      entity_2_sq.map do |ent2_pos|
        pos1_x, pos1_y = ent1_pos
        pos2_x, pos2_y = ent2_pos
        Math.sqrt((pos1_x - pos2_x)**2 + (pos1_y - pos2_y)**2).floor
      end
    end.flatten.min
  end

  # Get all the location of the squares occupied by said entity (e.g. for large, huge creatures)
  # @param entity [Entity]
  # @return [Array]
  def entity_squares(entity)
    pos1_x, pos1_y = entity_or_object_pos(entity)
    entity_1_squares = []
    (0...entity.token_size).each do |ofs_x|
      (0...entity.token_size).each do |ofs_y|
        entity_1_squares << [pos1_x + ofs_x, pos1_y + ofs_y]
      end
    end
    entity_1_squares
  end

  # Get all the location of the squares occupied by said entity (e.g. for large, huge creatures)
  # and use specified entity location instead of current location on the map
  # @param entity [Entity]
  # @param pos1_x [Integer]
  # @param pos1_y [Integer]
  # @return [Array]
  def entity_squares_at_pos(entity, pos1_x, pos1_y)
    entity_1_squares = []
    (0...entity.token_size).each do |ofs_x|
      (0...entity.token_size).each do |ofs_y|
        entity_1_squares << [pos1_x + ofs_x, pos1_y + ofs_y]
      end
    end
    entity_1_squares
  end

  # Entity to look around
  # @param entity [Entity] The entity to look around his line of sight
  # @return [Hash] entities in line of sight
  def look(entity, distance = nil)
    @entities.map do |k, v|
      next if k == entity

      pos1_x, pos1_y = v
      next unless line_of_sight_for_ex?(entity, k, distance)

      [k, [pos1_x, pos1_y]]
    end.compact.to_h
  end

  # Compute if entity is in line of sight
  # @param entity [Entity]
  # @param pos2_x [Integer]
  # @param pos2_y [Integer]
  # @param distance [Integer]
  # @return [TrueClass, FalseClass]
  def line_of_sight_for?(entity, pos2_x, pos2_y, distance = nil)
    raise 'cannot find entity' if @entities[entity].nil?

    pos1_x, pos1_y = @entities[entity]
    line_of_sight?(pos1_x, pos1_y, pos2_x, pos2_y, distance)
  end

  def line_of_sight_for_ex?(entity, entity2, distance = nil)
    raise 'cannot find entity' if @entities[entity].nil? && @interactable_objects[entity].nil?

    entity_1_squares = entity_squares(entity)
    entity_2_squares = entity_squares(entity2)

    entity_1_squares.each do |pos1|
      entity_2_squares.each do |pos2|
        pos1_x, pos1_y = pos1
        pos2_x, pos2_y = pos2
        return true if line_of_sight?(pos1_x, pos1_y, pos2_x, pos2_y, distance)
      end
    end
    false
  end

  def position_of(entity)
    entity.is_a?(ItemLibrary::Object) ? interactable_objects[entity] : @entities[entity]
  end

  # Get entity at map location
  # @param pos_x [Integer]
  # @param pos_y [Integer]
  def entity_at(pos_x, pos_y)
    entity_data = @tokens[pos_x][pos_y]
    return nil if entity_data.nil?

    entity_data[:entity]
  end

  # Get entity or object at map location
  # @param pos_x [Integer]
  # @param pos_y [Integer]
  def thing_at(pos_x, pos_y)
    [entity_at(pos_x, pos_y), object_at(pos_x, pos_y)].compact
  end

  def move_to!(entity, pos_x, pos_y)
    cur_x, cur_y = @entities[entity]

    entity_data = @tokens[cur_x][cur_y]

    (0...entity.token_size).each do |ofs_x|
      (0...entity.token_size).each do |ofs_y|
        @tokens[cur_x + ofs_x][cur_y + ofs_y] = nil
      end
    end

    (0...entity.token_size).each do |ofs_x|
      (0...entity.token_size).each do |ofs_y|
        @tokens[pos_x + ofs_x][pos_y + ofs_y] = entity_data
      end
    end

    @entities[entity] = [pos_x, pos_y]
  end

  def valid_position?(pos_x, pos_y)
    if pos_x >= @base_map.size || pos_x < 0 || pos_y >= @base_map[0].size || pos_y < 0
      return false
    end # check for out of bounds

    return false if @base_map[pos_x][pos_y] == '#'
    return false unless @tokens[pos_x][pos_y].nil?

    true
  end

  def movement_cost(entity, path, battle = nil)
    return 0 if path.empty?

    cost = 0
    path.each_with_index do |position, index|
      next unless index > 0

      cost += if difficult_terrain?(entity, *position, battle)
                2
              else
                1
              end
    end
    cost * 5
  end

  def passable?(entity, pos_x, pos_y, battle = nil)
    (0...entity.token_size).each do |ofs_x|
      (0...entity.token_size).each do |ofs_y|
        relative_x = pos_x + ofs_x
        relative_y = pos_y + ofs_y

        return false if relative_x >= @size[0]
        return false if relative_y >= @size[1]

        return false if @base_map[relative_x][relative_y] == '#'
        return false if object_at(relative_x, relative_y) && !object_at(relative_x, relative_y).passable?

        next unless battle && @tokens[relative_x][relative_y]

        location_entity = @tokens[relative_x][relative_y][:entity]

        source_state = battle.entity_state_for(entity)
        source_group = source_state[:group]
        location_state = battle.entity_state_for(location_entity)
        next if @tokens[relative_x][relative_y][:entity] == entity

        location_group = location_state[:group]
        next if location_group.nil?
        next if location_group == source_group
        if location_group != source_group && (location_entity.size_identifier - entity.size_identifier).abs < 2
          return false
        end
      end
    end

    true
  end

  def placeable?(entity, pos_x, pos_y, battle = nil)
    return false unless passable?(entity, pos_x, pos_y, battle)

    entity_squares_at_pos(entity, pos_x, pos_y).each do |pos|
      p_x, p_y = pos
      next if @tokens[p_x][p_y] && @tokens[p_x][p_y][:entity] == entity
      return false if @tokens[p_x][p_y] && !@tokens[p_x][p_y][:entity].dead?
      return false if object_at(p_x, p_y) && !object_at(p_x, p_y)&.passable?
    end

    true
  end

  def difficult_terrain?(entity, pos_x, pos_y, _battle = nil)
    return false if @tokens[pos_x][pos_y] && @tokens[pos_x][pos_y][:entity] == entity
    return true if @tokens[pos_x][pos_y] && !@tokens[pos_x][pos_y][:entity].dead?

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
      object_at(pos_x, pos_y).opaque?
    end
  end

  def line_of_sight?(pos1_x, pos1_y, pos2_x, pos2_y, distance = nil)
    return true if [pos1_x, pos1_y] == [pos2_x, pos2_y]

    if pos2_x == pos1_x
      scanner = pos2_y > pos1_y ? (pos1_y...pos2_y) : (pos2_y...pos1_y)

      scanner.each_with_index do |y, index|
        return false if !distance.nil? && index > distance
        next if (y == pos1_y) || (y == pos2_y)
        return false if opaque?(pos1_x, y)
      end
      true
    else
      m = (pos2_y - pos1_y).to_f / (pos2_x - pos1_x).to_f
      if m == 0
        scanner = pos2_x > pos1_x ? (pos1_x...pos2_x) : (pos2_x...pos1_x)

        scanner.each_with_index do |x, index|
          return false if !distance.nil? && index > distance
          next if (x == pos1_x) || (x == pos2_x)
          return false if opaque?(x, pos2_y)
        end

        true
      else
        scanner = pos2_x > pos1_x ? (pos1_x...pos2_x) : (pos2_x...pos1_x)

        b = pos1_y - m * pos1_x
        step = m.abs > 1 ? 1 / m.abs : m.abs

        scanner.step(step).each_with_index do |x, index|
          y = (m * x + b).round

          return false if !distance.nil? && index > distance
          next if (x.round == pos1_x && y == pos1_y) || (x.round == pos2_x && y == pos2_y)
          return false if opaque?(x.round, y)
        end
        true
      end
    end
  end

  def npc_token(pos_x, pos_y)
    entity = @tokens[pos_x][pos_y]
    color = (entity[:entity]&.color.presence || :white).to_sym
    token = if entity[:entity].token
              m_x, m_y = @entities[entity[:entity]]
              entity[:entity].token[pos_y - m_y][pos_x - m_x]
            else
              @tokens[pos_x][pos_y][:token]
            end
    token.colorize(color)
  end

  def object_token(pos_x, pos_y)
    object_meta = object_at(pos_x, pos_y)
    m_x, m_y = @interactable_objects[object_meta]
    color = (object_meta.color.presence || :white).to_sym

    return nil unless object_meta.token

    object_meta.token[pos_y - m_y][pos_x - m_x].colorize(color)
  end

  def render_position(c, col_index, row_index, path: [], line_of_sight: nil)
    c = case c
        when '.'
          '·'.colorize(:light_black)
        when '#'
          '#'
        else
          object_token(col_index, row_index) || c
        end

    if !path.empty?
      return 'X' if path[0] == [col_index, row_index]
      return '+' if path.include?([col_index, row_index])
      return ' ' if line_of_sight && !line_of_sight?(path.last[0], path.last[1], col_index, row_index)
    else
      has_line_of_sight = if line_of_sight.is_a?(Array)
                            line_of_sight.detect { |l| line_of_sight_for?(l, col_index, row_index) }
                          elsif line_of_sight
                            line_of_sight_for?(line_of_sight, col_index, row_index)
                          end
      return ' ' if line_of_sight && !has_line_of_sight
    end

    # render map layer
    return '`' if @tokens[col_index][row_index]&.fetch(:entity)&.dead?

    token = @tokens[col_index][row_index] ? npc_token(col_index, row_index) : nil
    token || c
  end

  def render(line_of_sight: nil, path: [], select_pos: nil)
    @base_map.transpose.each_with_index.map do |row, row_index|
      row.each_with_index.map do |c, col_index|
        display = render_position(c, col_index, row_index, path: path, line_of_sight: line_of_sight)
        if select_pos && select_pos == [col_index, row_index]
          display.colorize(color: :black, background: :white)
        else
          display
        end
      end.join
    end.join("\n") + "\n"
  end

  protected

  def entity_or_object_pos(thing)
    thing.is_a?(ItemLibrary::Object) ? @interactable_objects[thing] : @entities[thing]
  end
end
