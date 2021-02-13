module Natural20::SpellAttackHelper
  include Natural20::Cover
  include Natural20::AttackHelper

  def evaluate_spell_attack(battle, entity, target, spell_properties)
    # DnD 5e advantage/disadvantage checks
    advantage_mod, _adv_info = target_advantage_condition(battle, entity, target, spell_properties)

    attack_roll = entity.ranged_spell_attack!(battle, spell_properties[:name], advantage: advantage_mod.positive?,
                                                                               disadvantage: advantage_mod.negative?)

    target_ac, _cover_ac = effective_ac(
      battle, target
    )

    force_miss = after_attack_roll_hook(battle, target,
                                        source, attack_roll, target_ac, spell: spell_properties)
    if !force_miss
      cover_ac_adjustments = 0
      hit = if attack_roll.nat_20?
              true
            elsif attack_roll.nat_1?
              false
            else
              target_ac, cover_ac_adjustments = effective_ac(battle, target)
              attack_roll.result >= target_ac
            end
    else
      hit = false
    end
    [hit, attack_roll, advantage_mod, cover_ac_adjustments]
  end
end
