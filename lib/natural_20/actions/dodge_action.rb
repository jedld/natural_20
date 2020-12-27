class DodgeAction < Action
  attr_accessor :as_bonus_action

  def self.can?(entity, battle)
    battle && entity.total_actions(battle) > 0
  end

  def build_map
    OpenStruct.new({
      param: nil,
      next: ->() { self },
    })
  end

  def self.build(session, source)
    action = DodgeAction.new(session, source, :attack)
    action.build_map
  end

  def resolve(session, map, opts = {})
    @result = [{
      source: @source,
      type: :dodge,
      battle: opts[:battle],
    }]
    self
  end

  def apply!(battle)
    @result.each do |item|
      case (item[:type])
      when :dodge
        EventManager.received_event({source: item[:source], event: :dodge })
        item[:source].dodging!(battle)
      end

      if as_bonus_action
        battle.entity_state_for(item[:source])[:bonus_action] -= 1
      else
        battle.entity_state_for(item[:source])[:action] -= 1
      end
    end
  end
end
