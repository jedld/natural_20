module ItemLibrary
  class Object
    class InvalidInteractionAction < StandardError
      attr_reader :action, :valid_actions

      # @param action [Symbol]
      # @param valid_actions [Array]
      def initialize(action, valid_actions = [])
        @action = action
        @valid_actions = valid_actions
      end

      def message
        "Invalid action specified #{action}. should be in #{valid_actions.join(',')}"
      end
    end

    include Entity

    attr_accessor :hp, :statuses, :resistances, :name, :map

    def initialize(map, properties)
      @name = properties[:name]
      @map = map
      @statuses = Set.new
      @properties = properties
      @resistances = properties[:resistances].presence || []
      setup_other_attributes
      @hp = DieRoll.roll(properties[:hp_die] || properties[:max_hp]).result
    end

    def position
      map.position_of(self)
    end

    def color
      @properties[:color]
    end

    def armor_class
      @properties[:default_ac]
    end

    def opaque?
      true
    end

    def token
    end

    def size
      @properties[:size] || :medium
    end

    def available_actions(entity, battle)
      []
    end

    def passable?
      false
    end

    def describe_health
      ""
    end

    def npc?
      true
    end

    protected

    def setup_other_attributes
    end
  end
end