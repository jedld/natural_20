# typed: false
module Natural20::WizardClass
  WIZARD_SPELL_SLOT_TABLE =
    [
      # cantrips, 1st, 2nd, 3rd ... etc
      [3, 2], # 1
      [3, 3], # 2
      [3, 4, 2], # 3
      [4, 4, 3], # 4
      [4, 4, 3, 2], # 5
      [4, 4, 3, 3], # 6
      [4, 4, 3, 3, 1], # 7
      [4, 4, 3, 3, 2], # 8
      [4, 4, 3, 3, 3, 1], # 9
      [5, 4, 3, 3, 3, 2], # 10
      [5, 4, 3, 3, 3, 2, 1], # 11
      [5, 4, 3, 3, 3, 2, 1], # 12
      [5, 4, 3, 3, 3, 2, 1, 1], # 13
      [5, 4, 3, 3, 3, 2, 1, 1], # 14
      [5, 4, 3, 3, 3, 2, 1, 1, 1], # 15
      [5, 4, 3, 3, 3, 2, 1, 1, 1], # 16
      [5, 4, 3, 3, 3, 2, 1, 1, 1, 1], # 17
      [5, 4, 3, 3, 3, 3, 1, 1, 1, 1], # 18
      [5, 4, 3, 3, 3, 3, 2, 1, 1, 1], # 19
      [5, 4, 3, 3, 3, 3, 2, 2, 1, 1] # 20
    ].freeze

  attr_accessor :wizard_level, :wizard_spell_slots

  def initialize_wizard
    @spell_slots[:wizard] = reset_spell_slots
  end

  def spell_attack_modifier
    proficiency_bonus + int_mod
  end

  def special_actions_for_wizard(_session, _battle)
    []
  end

  protected

  def reset_spell_slots
    WIZARD_SPELL_SLOT_TABLE[wizard_level - 1].each_with_index.map do |slots, index|
      [index, slots]
    end.to_h
  end
end
