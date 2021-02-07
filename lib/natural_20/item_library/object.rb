# typed: true
module ItemLibrary
  module AreaTrigger
    def area_trigger_handler(_entity, _entity_pos, is_flying); end
  end

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

    include Natural20::Entity
    include Natural20::Notable

    attr_accessor :hp, :statuses, :resistances, :name, :map

    def initialize(map, properties)
      @name = properties[:name]
      @map = map
      @session = map.session
      @statuses = Set.new
      @properties = properties
      @resistances = properties[:resistances].presence || []
      setup_other_attributes
      @hp = if !properties[:hp_die].blank?
              Natural20::DieRoll.roll(properties[:hp_die]).result
            else
              properties[:max_hp]
            end
      if @properties[:inventory]
        @inventory = @properties[:inventory].map do |inventory|
          [inventory[:type].to_sym, OpenStruct.new({ qty: inventory[:qty] })]
        end.to_h
      end
    end

    def name
      @properties[:label] || @name
    end

    def label
      @properties[:label] || name
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
      @properties[:opaque]
    end

    def half_cover?
      @properties[:cover] == 'half'
    end

    def cover_ac
      case @properties[:cover].to_sym
      when :half
        2
      when :three_quarter
        5
      else
        0
      end
    end

    def three_quarter_cover?
      @properties[:cover] == 'three_quarter'
    end

    def total_cover?
      @properties[:cover] == 'total'
    end

    def can_hide?
      @properties.fetch(:allow_hide, false)
    end

    def interactable?
      false
    end

    def placeable?
      @properties.key?(:placeable) ? @properties[:placeable] : true
    end

    def movement_cost
      @properties[:movement_cost] || 1
    end

    def token
      @properties[:token]
    end

    def size
      @properties[:size] || :medium
    end

    def available_interactions(_entity, _battle)
      []
    end

    def light_properties
      @properties[:light]
    end

    # This terrain needs to be jumped over for movement
    def jump_required?
      @properties[:jump]
    end

    def passable?
      @properties[:passable]
    end

    def wall?
      @properties[:wall]
    end

    def concealed?
      false
    end

    def describe_health
      ''
    end

    def object?
      true
    end

    def npc?
      false
    end

    def pc?
      false
    end

    def items_label
      I18n.t(:"object.#{self.class}.item_label", default: "#{name} Items")
    end

    protected

    def setup_other_attributes; end
  end
end
