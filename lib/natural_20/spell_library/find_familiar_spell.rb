class Natural20::FindFamiliarSpell < Natural20::Spell
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
    when :find_familiar
      Natural20::EventManager.received_event(event: :spell_buf, spell: item[:effect], source: item[:source],
                                             target: item[:target])
      SpellAction.consume_resource(battle, item)
    end
  end

  # @param entity [Natural20::Entity]
  # @param battle [Natrual20::Battle]
  # @param spell_action [Natural20::SpellAction]
  def resolve(entity, _battle, _spell_action)
    [{
      type: :find_familiar,
      familiar: familiar,
      target: entity,
      source: entity,
      effect: self,
      spell: @properties
    }]
  end
end
