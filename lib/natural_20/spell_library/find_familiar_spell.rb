class Natural20::FindFamiliarSpell < Natural20::Spell
  attr_accessor :familiar

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
      end.map do |f, details|
        [f, details[:kind]]
      end
    end
  end

  # @param battle [Natural20::Battle]
  def self.apply!(battle, item)
    case item[:type]
    when :find_familiar
      npc = item[:familiar]

      battle.add(npc, battle.entity_group_for(item[:source]), controller: battle.controller_for(item[:source]),
                                                              position: item[:position])
      item[:source].add_casted_effect({ target: item[:target], effect: item[:effect] })
      Natural20::EventManager.received_event(event: :spell_buf, spell: item[:effect], source: item[:source],
                                             target: item[:target])
      SpellAction.consume_resource(battle, item)
    end
  end

  # @param entity [Natural20::Entity]
  # @param battle [Natrual20::Battle]
  # @param spell_action [Natural20::SpellAction]
  def resolve(entity, battle, spell_action)
    npc = battle.session.npc(spell_action.other_params,
                             { name: "#{entity.name}'s Familiar (#{spell_action.other_params.humanize})" })
    @familiar = npc
    [{
      type: :find_familiar,
      familiar: npc,
      position: spell_action.target,
      source: entity,
      effect: self,
      spell: @properties
    }]
  end
end
