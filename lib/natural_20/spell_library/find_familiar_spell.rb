class Natural20::FindFamiliarSpell < Natural20::Spell
  def build_map(action)
    OpenStruct.new({
                     param: [
                       {
                         type: :select_target,
                         num: 1,
                         range: @properties[:range],
                         target_types: %i[square]
                       },
                       {
                         type: :select,
                         num: 1,
                         choices: familiars
                       }
                     ],
                     next: lambda { |target, familiar|
                             action.target = target
                             action.other_params = familiar
                             OpenStruct.new({
                                              param: nil,
                                              next: lambda {
                                                      action
                                                    }
                                            })
                           }
                   })
  end

  def familiars
    @familiars ||= begin
      session.npc_info.select do |_name, details|
        details[:familiar]
      end.map { |f, details|
        [f, details[:kind]] }
    end
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
  def resolve(entity, _battle, spell_action)
    [{
      type: :find_familiar,
      familiar: spell_action.other_params,
      position: target,
      source: entity,
      effect: self,
      spell: @properties
    }]
  end
end
