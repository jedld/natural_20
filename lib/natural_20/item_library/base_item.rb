# typed: true
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

    def item?
      true
    end

    def use!(battle, map, entity); end

    protected

    def t(key, options = {})
      I18n.t(key, **options)
    end
  end
end
