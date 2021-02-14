class Natural20::ShockingGraspSpell < Natural20::Spell
  include Natural20::Cover
  include Natural20::Weapons
  include Natural20::SpellAttackHelper

  def build_map(action)
    OpenStruct.new({
                     param: [
                       {
                         type: :select_target,
                         num: 1,
                         range: 5,
                         target_types: %i[enemies]
                       }
                     ],
                     next: lambda { |target|
                             action.target = target
                             OpenStruct.new({
                                              param: nil,
                                              next: lambda {
                                                      action
                                                    }
                                            })
                           }
                   })
  end

  # @param entity [Natural20::Entity]
  # @param battle [Natrual20::Battle]
  # @param spell_action [Natural20::SpellAction]
  def resolve(entity, battle, spell_action)
    target = spell_action.target
    advantage_override = {}

    advantage_override[:advantage] = [:shocking_grasp_metallic] if target.equipped_armor.detect(&:metallic)

    hit, attack_roll, advantage_mod, cover_ac_adjustments = evaluate_spell_attack(battle, entity, target, @properties,
                                                                                  advantage_override)

    if hit
      level = 1
      level += 1 if entity.level >= 5
      level += 1 if entity.level >= 11
      level += 1 if entity.level >= 17

      damage_roll = Natural20::DieRoll.roll("#{level}d8", crit: attack_roll.nat_20?, battle: battle, entity: entity,
                                                          description: t('dice_roll.spells.generic_damage', spell: t('spell.shocking_grasp')))
      [{
        source: entity,
        target: target,
        attack_name: t('spell.shocking_grasp'),
        damage_type: @properties[:damage_type],
        attack_roll: attack_roll,
        damage_roll: damage_roll,
        advantage_mod: advantage_mod,
        damage: damage_roll,
        cover_ac: cover_ac_adjustments,
        type: :spell_damage,
        spell: @properties
      },
       {
         source: entity,
         target: target,
         type: :shocking_grasp,
         effect: self
       }]
    else
      [{
        type: :spell_miss,
        source: entity,
        target: target,
        attack_name: t('spell.firebolt'),
        damage_type: @properties[:damage_type],
        attack_roll: attack_roll,
        damage_roll: damage_roll,
        advantage_mod: advantage_mod,
        cover_ac: cover_ac_adjustments,
        spell: @properties
      }]
    end
  end

  # @param battle [Natural20::Battle]
  def self.apply!(battle, item)
    case item[:type]
    when :shocking_grasp
      battle.entity_state_for(item[:target])&.merge!(reaction: 0)
    end
  end
end
