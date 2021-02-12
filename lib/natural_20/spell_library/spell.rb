class Natural20::Spell
  attr_accessor :errors
  attr_reader :properties, :source

  def initialize(source, spell_name, details)
    @name = spell_name
    @properties = details
    @source = source
    @errors = []
  end

  def label
    t(:"spell.#{@name}")
  end

  def id
    @properties[:id]
  end

  def self.apply!(battle, item); end

  def validate!(_action)
    @errors.clear
  end

  protected

  def t(token, options = {})
    I18n.t(token, options)
  end
end
