# class used for ray trace and path trace computations
class RayTracer
  def initialize(map)
    @map = map
  end

  def ray_trace(pos1_x, pos1_y, pos2_x, pos2_y, max_distance)
    return true if [pos1_x, pos1_y] == [pos2_x, pos2_y]

    if pos2_x == pos1_x
      scanner = pos2_y > pos1_y ? (pos1_y...pos2_y) : (pos2_y...pos1_y)

      scanner.each_with_index do |y, index|
        return false if !distance.nil? && index > distance
        next if (y == pos1_y) || (y == pos2_y)
        return false if @map.opaque?(pos1_x, y)
      end
      true
    else
      m = (pos2_y - pos1_y).to_f / (pos2_x - pos1_x).to_f
      if m == 0
        scanner = pos2_x > pos1_x ? (pos1_x...pos2_x) : (pos2_x...pos1_x)

        scanner.each_with_index do |x, index|
          return false if !distance.nil? && index > distance
          next if (x == pos1_x) || (x == pos2_x)
          return false if @map.opaque?(x, pos2_y)
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
          return false if @map.opaque?(x.round, y)
        end
        true
      end
    end
  end

  def line_of_sight?(pos1_x, pos1_y, pos2_x, pos2_y, distance = nil)
    return true if [pos1_x, pos1_y] == [pos2_x, pos2_y]

    if pos2_x == pos1_x
      scanner = pos2_y > pos1_y ? (pos1_y...pos2_y) : (pos2_y...pos1_y)

      scanner.each_with_index do |y, index|
        return false if !distance.nil? && index > distance
        next if (y == pos1_y) || (y == pos2_y)
        return false if @map.opaque?(pos1_x, y)
      end
      true
    else
      m = (pos2_y - pos1_y).to_f / (pos2_x - pos1_x).to_f
      if m == 0
        scanner = pos2_x > pos1_x ? (pos1_x...pos2_x) : (pos2_x...pos1_x)

        scanner.each_with_index do |x, index|
          return false if !distance.nil? && index > distance
          next if (x == pos1_x) || (x == pos2_x)
          return false if @map.opaque?(x, pos2_y)
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
          return false if @map.opaque?(x.round, y)
        end
        true
      end
    end
  end
end
