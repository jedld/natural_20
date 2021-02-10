# typed: false
module Natural20::WizardClass
  attr_accessor :wizard_level

  def initialize_wizard
  end

  def spell_attack_modifier
    proficiency_bonus + int_mod
  end

  def special_actions_for_wizard(session, battle)
    []
  end
end
