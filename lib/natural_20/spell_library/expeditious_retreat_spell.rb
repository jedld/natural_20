class Natural20::ExpeditiousRetreatSpell < Natural20::Spell
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
    when :expeditious_retreat

      item[:source].add_casted_effect({ target: item[:target], effect: item[:effect],
                                        expiration: battle.session.game_time + 10.minutes.to_i })
      item[:target].register_effect(:dash_override, self, effect: item[:effect], source: item[:source],
                                                          duration: 10.minutes.to_i)
      Natural20::EventManager.received_event(event: :spell_buf, spell: item[:effect], source: item[:source],
                                             target: item[:target])
      SpellAction.consume_resource(battle, item)
    end
  end

  def self.dash_override(entity, effect, opts = {})
    true
  end

  # @param entity [Natural20::Entity]
  # @param battle [Natrual20::Battle]
  # @param spell_action [Natural20::SpellAction]
  def resolve(entity, _battle, _spell_action)
    [{
      type: :expeditious_retreat,
      target: entity,
      source: entity,
      effect: self,
      spell: @properties
    }]
  end
end
