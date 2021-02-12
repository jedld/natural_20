class Natural20::MagicMissile < Natural20::Spell
  include Natural20::Cover
  include Natural20::Weapons
  include Natural20::AttackHelper

  def build_map(action)
    cast_level = action.at_level || 1
    darts = 3 + (cast_level - 1)

    OpenStruct.new({
                     param: [
                       {
                         type: :select_target,
                         num: darts,
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
    targets = spell_action.target

    targets.map do |target|
      after_attack_roll_hook(battle, target,
        entity, nil, nil, spell: @properties)

      if target.has_spell_effect?(:shield)
        {
          source: entity,
          target: target,
          attack_name: t('spell.magic_missile'),
          damage_type: @properties[:damage_type],
          type: :spell_miss,
          spell: @properties
        }
      else
        damage_roll = Natural20::DieRoll.roll('1d4+1', battle: battle, entity: entity,
                                                       description: t('dice_roll.spells.magic_missile'))

        {
          source: entity,
          target: target,
          attack_name: t('spell.magic_missile'),
          damage_type: @properties[:damage_type],
          damage_roll: damage_roll,
          damage: damage_roll,
          type: :spell_damage,
          spell: @properties
        }
      end
    end
  end
end
