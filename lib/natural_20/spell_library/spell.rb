class Natural20::Spell
  attr_accessor :errors
  attr_reader :properties

  def initialize(spell_name, details)
    @name = spell_name
    @properties = details
    @errors = []
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
