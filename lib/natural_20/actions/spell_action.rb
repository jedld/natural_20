class SpellAction < Natural20::Action
  attr_accessor :target, :spell_action, :other_params

  def self.can?(entity, battle, _options = {})
    return false unless entity.has_spells?

    battle.nil? || !battle.ongoing? || can_cast?(entity, battle, spell)
  end

  # @param battle [Natural20::Battle]
  # @param spell [Symbol]
  def self.can_cast?(entity, battle, spell)
    spell_details = battle.session.load_spell(spell)
    amt, resource = spell_details[:casting_time].split(':')

    return true if resource == ('action') && battle.total_actions(entity).positive?

    false
  end

  def self.build(session, source)
    action = SpellAction.new(session, source, :spell)
    action.build_map
  end

  def build_map
    OpenStruct.new({
                     action: self,
                     param: [
                       {
                         type: :select_spell
                       }
                     ],
                     next: lambda { |spell|
                             spell_details = session.load_spell(spell)
                             @spell_action = spell_details[:spell_class].constantize.new(spell, spell_details)
                             @spell_action.build_map(self)
                           }
                   })
  end

  def resolve(_session, map = nil, opts = {})
    battle = opts[:battle]
    result_payload = {
      source: @source,
      target: target,
      map: map,
      battle: battle,
      type: :cast_spell,
      item: spell_action
    }.merge(spell_action.resolve(@source, battle))
    @result = [result_payload]
    self
  end

  def self.apply!(battle, item)
    case item[:type]
    when :cast_spell
      Natural20::EventManager.received_event({ event: :cast_spell, source: item[:source], item: item[:item] })
      item[:item].use!(item[:target], item)
      battle.entity_state_for(item[:source])[:action] -= 1 if battle
    end
  end
end
