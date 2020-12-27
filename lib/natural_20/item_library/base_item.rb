module ItemLibrary
  class BaseItem
    attr_reader :name

    def initialize(name, properties)
      @name = name
      @properties = properties
    end

    def consumable?
      !!@properties[:consumable]
    end

    def use!(battle, map, entity)

    end
  end
end
