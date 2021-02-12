class Natural20::Shield < Natural20::Spell
  def build_map(action)
    OpenStruct.new({
                     param: nil,
                     next: lambda {
                             action
                           }
                   })
  end

  def self.apply!(battle, item)
    case item[:type]
    when :shield

      item[:source].add_casted_effect(effect: item[:effect])
      item[:target].register_effect(:ac_bonus, self, effect: item[:effect], source: item[:source],
                                                     duration: 8.hours.to_i)

      item[:target].register_event_hook(:start_of_turn, self, effect: item[:effect], effect: item[:effect],
                                                              source: item[:source])
      Natural20::EventManager.received_event(event: :spell_buf, spell: item[:effect], source: item[:source],
                                             target: item[:source])
      SpellAction.consume_resource(battle, item)
    end
  end

  # @param entity [Natural20::Entity]
  # @param effect [Object]
  def self.ac_bonus(_entity, _effect)
    5
  end

  def self.start_of_turn(entity, opts = {})
    entity.dismiss_effect!(opts[:effect])
  end

  # @param battle [Natural20::Battle]
  # @param entity [Natural20::Entity]
  # @param attacker [Natural20::Entity]
  # @param attack_roll [Natural20::DieRoll]
  def self.after_attack_roll(battle, entity, _attacker, attack_roll)
    if attack_roll.result.between?(entity.armor_class, entity.armor_class + 4)
      spell = battle.session.load_spell('shield')
      [{
        type: :shield,
        target: entity,
        source: entity,
        effect: Natural20::Shield.new(entity, 'shield', spell),
        spell: spell
      }]
    else
      []
    end
  end

  # @param entity [Natural20::Entity]
  # @param battle [Natrual20::Battle]
  # @param spell_action [Natural20::SpellAction]
  def resolve(_entity, _battle, spell_action)
    [{
      type: :shield,
      target: spell_action.source,
      source: spell_action.source,
      effect: self,
      spell: @properties
    }]
  end
end
