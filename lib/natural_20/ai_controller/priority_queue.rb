module AiController
  class PriorityQueue
    def initialize
      @arr = []
      @node_to_index = {}
    end

    def add_node(node, priority)
      if @node_to_index.include?(node)
        update_priority(node, priority)
        return
      end

      index = @arr.size

      @arr[index] = [node, priority]
      @node_to_index[node] = index

      upheapify(index)
    end

    def pop
      return nil if @arr.empty?

      result = @arr[0]
      @node_to_index.delete(result.first)

      @arr[0] = @arr[@arr.size - 1]
      @arr.delete_at(@arr.size - 1)

      unless @arr.empty?
        @node_to_index[@arr[0].first] = 0

        downheapify(0)
      end
      result
    end

    def update_priority(node, priority)
      index = @node_to_index[node]
      @arr[index][1] = priority
      downheapify(index)
      upheapify(index)
    end

    def pop_to_arr
      arr = []
      loop do
        result = pop
        return arr if result.nil?

        arr << result.first
      end
    end

    protected

    def downheapify(index)
      loop do
        left_index = (index * 2) + 1
        right_index = (index * 2) + 2

        return if @arr[left_index].nil? && @arr[right_index].nil?

        if @arr[left_index] && @arr[right_index] && (@arr[left_index].second < @arr[right_index].second) && (@arr[index].second > @arr[left_index].second)
          @arr[left_index], @arr[index] = @arr[index], @arr[left_index]
          @node_to_index[@arr[left_index].first] = left_index
          @node_to_index[@arr[index].first] = index
          index = left_index
          next
        end

        if @arr[right_index] && (@arr[index].second > @arr[right_index].second)
          @arr[right_index], @arr[index] = @arr[index], @arr[right_index]
          @node_to_index[@arr[right_index].first] = left_index
          @node_to_index[@arr[index].first] = index
          index = right_index
          next
        end

        if @arr[left_index] && (@arr[index].second > @arr[left_index].second)
          @arr[left_index], @arr[index] = @arr[index], @arr[left_index]
          @node_to_index[@arr[left_index].first] = left_index
          @node_to_index[@arr[index].first] = index
          index = left_index
          next
        end

        break
      end
    end

    def upheapify(index)
      loop do
        return if index.zero?

        parent_index = (index / 2).floor
        break if @arr[parent_index].second < @arr[index].second

        @arr[parent_index], @arr[index] = @arr[index], @arr[parent_index]
        @node_to_index[@arr[parent_index].first] = parent_index
        @node_to_index[@arr[index].first] = index

        index = parent_index
      end
    end
  end
end
