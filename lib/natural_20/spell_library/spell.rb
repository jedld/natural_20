class Natural20::Spell
  def initialize(spell_name, details)
    @name = spell_name
    @properties = details
  end

  def self.apply!(battle, item); end

  protected

  def t(token, options = {})
    I18n.t(token, options)
  end
end
