class Natural20::RayOfFrostSpell < Natural20::Spell
  include Natural20::Cover
  include Natural20::Weapons
  include Natural20::SpellAttackHelper

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

    hit, attack_roll, advantage_mod, cover_ac_adjustments = evaluate_spell_attack(battle, entity, target, @properties)

    if hit
      level = 1
      level += 1 if entity.level >= 5
      level += 1 if entity.level >= 11
      level += 1 if entity.level >= 17

      damage_roll = Natural20::DieRoll.roll("#{level}d8", crit: attack_roll.nat_20?, battle: battle, entity: entity,
                                                          description: t('dice_roll.spells.ray_of_frost'))
      [{
        source: entity,
        target: target,
        attack_name: t('spell.ray_of_frost'),
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
         type: :ray_of_frost,
         effect: self
       }]
    else
      [{
        type: :spell_miss,
        source: entity,
        target: target,
        attack_name: t('spell.ray_of_frost'),
        damage_type: @properties[:damage_type],
        attack_roll: attack_roll,
        damage_roll: damage_roll,
        advantage_mod: advantage_mod,
        cover_ac: cover_ac_adjustments,
        spell: @properties
      }]
    end
  end

  # @param entity [Natural20::Entity]
  def self.start_of_turn(_entity, opt = {})
    opt[:effect].action.target.dismiss_effect!(opt[:effect])
  end

  def self.speed_override(_entity, opt = {})
    [opt[:value] - 10, 0].max
  end

  # @param battle [Natural20::Battle]
  def self.apply!(_battle, item)
    case item[:type]
    when :ray_of_frost
      item[:source].add_casted_effect(target: item[:target], effect: item[:effect])
      item[:target].register_effect(:speed_override, self, effect: item[:effect], source: item[:source])
      item[:source].register_event_hook(:start_of_turn, self, effect: item[:effect])
    end
  end
end
