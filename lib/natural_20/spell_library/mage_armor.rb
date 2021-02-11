class Natural20::MageArmor < Natural20::Spell
  def build_map(action)
    OpenStruct.new({
                     param: [
                       {
                         type: :select_target,
                         num: 1,
                         range: 5,
                         target_types: %i[allies self]
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

  def validate!(action)
    @errors.clear
    @errors << :wearing_armor if action.target.wearing_armor?
  end

  def self.apply!(battle, item)
    case item[:type]
    when :mage_armor

      item[:source].add_casted_effect({ target: item[:target], effect: item[:effect], expiration: battle.session.game_time + 8.hours.to_i })
      item[:target].register_effect(:ac_override, self, effect: item[:effect], source: item[:source],
                                                        duration: 8.hours.to_i)
      item[:target].register_event_hook(:equip, self, effect: item[:effect], effect: item[:effect],
                                                      source: item[:source],
                                                      duration: 8.hours.to_i)
      Natural20::EventManager.received_event(event: :spell_buf, spell: item[:effect], source: item[:source],
                                             target: item[:target])
      SpellAction.consume_resource(battle, item)
    end
  end

  # @param entity [Natural20::Entity]
  # @param effect [Object]
  def self.ac_override(entity, _effect)
    13 + entity.dex_mod
  end

  def self.equip(entity, opts = {})
    entity.dismiss_effect!(opts[:effect]) if entity.wearing_armor?
  end

  # @param entity [Natural20::Entity]
  # @param battle [Natrual20::Battle]
  # @param spell_action [Natural20::SpellAction]
  def resolve(_entity, _battle, spell_action)
    [{
      type: :mage_armor,
      target: spell_action.target,
      source: spell_action.source,
      effect: self,
      spell: @properties
    }]
  end
end
