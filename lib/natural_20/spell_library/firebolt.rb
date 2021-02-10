class Natural20::Firebolt < Natural20::Spell
  include Natural20::Cover
  include Natural20::Weapons

  def build_map(action)
    OpenStruct.new({
                     param: [
                       {
                         type: :select_target,
                         num: 1,
                         range: @properties[:range],
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

    # DnD 5e advantage/disadvantage checks
    advantage_mod, adv_info = target_advantage_condition(battle, entity, target, @properties)

    attack_roll = entity.ranged_spell_attack!(battle, @properties[:name], advantage: advantage_mod.positive?,
                                                                          disadvantage: advantage_mod.negative?)

    cover_ac_adjustments = 0
    hit = if attack_roll.nat_20?
            true
          elsif attack_roll.nat_1?
            false
          else
            cover_ac_adjustments = calculate_cover_ac(battle.map, entity, target) if battle.map
            attack_roll.result >= (target.armor_class + cover_ac_adjustments)
          end

    if hit
      level = 1
      level += 1 if entity.level >= 5
      level += 1 if entity.level >= 11
      level += 1 if entity.level >= 17

      damage_roll = Natural20::DieRoll.roll("#{level}d10", crit: attack_roll.nat_20?, battle: battle, entity: entity,
                                                           description: t('dice_roll.spells.firebolt'))
      [{
        source: entity,
        target: target,
        attack_name: t('spell.firebolt'),
        damage_type: @properties[:damage_type],
        attack_roll: attack_roll,
        damage_roll: damage_roll,
        advantage_mod: advantage_mod,
        damage: damage_roll,
        cover_ac: cover_ac_adjustments,
        type: :spell_damage,
        spell: @properties
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

  protected

  # Computes cover armor class adjustment
  # @param map [Natural20::BattleMap]
  # @param target [Natural20::Entity]
  # @return [Integer]
  def calculate_cover_ac(map, entity, target)
    cover_calculation(map, entity, target)
  end
end
