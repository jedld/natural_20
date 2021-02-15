class Natural20::TrueStrikeSpell < Natural20::Spell
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
  def self.start_of_turn(entity, opt = {})
    entity.register_effect(:attack_advantage_modifier, self, effect: opt[:effect],
                                                             source: opt[:effect].action.source)
    entity.register_event_hook(:attack_resolved, self, effect: opt[:effect])
  end

  def self.attack_advantage_modifier(_entity, opt = {})
    if opt[:target] == opt[:effect].action.target
      [[:true_strike_advantage], []]
    else
      [[], []]
    end
  end

  # @param entity [Natural20::Entity]
  def self.end_of_turn(entity, opt = {})
    entity.dismiss_effect!(opt[:effect]) if entity.has_effect?(opt[:effect])
  end

  def self.attack_resolved(entity, opt = {})
    entity.dismiss_effect!(opt[:effect]) if opt[:target] == opt[:effect].action.target
  end

  def self.apply!(battle, item)
    case item[:type]
    when :true_strike
      item[:source].add_casted_effect({ target: item[:target], effect: item[:effect] })
      item[:source].concentration_on!(item[:effect])
      item[:source].register_event_hook(:start_of_turn, self, effect: item[:effect])
      item[:source].register_event_hook(:end_of_turn, self, effect: item[:effect])
      SpellAction.consume_resource(battle, item)
    end
  end

  # @param entity [Natural20::Entity]
  # @param battle [Natrual20::Battle]
  # @param spell_action [Natural20::SpellAction]
  def resolve(_entity, _battle, spell_action)
    [{
      type: :true_strike,
      target: spell_action.target,
      source: spell_action.source,
      effect: self,
      spell: @properties
    }]
  end
end
