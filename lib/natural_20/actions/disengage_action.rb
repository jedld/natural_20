class DisengageAction < Action
  attr_accessor :as_bonus_action

  def self.can?(entity, battle)
    battle && entity.total_actions(battle) > 0
  end

  def build_map
    OpenStruct.new({
                     param: nil,
                     next: -> { self }
                   })
  end

  def self.build(session, source)
    action = DisengageAction.new(session, source, :attack)
    action.build_map
  end

  def resolve(_session, _map, opts = {})
    @result = [{
      source: @source,
      type: :disengage,
      battle: opts[:battle]
    }]
    self
  end

  def apply!(battle)
    @result.each do |item|
      case (item[:type])
      when :disengage
        EventManager.received_event({ source: item[:source], event: :disengage })
        item[:source].disengage!(battle)
      end

      if as_bonus_action
        battle.entity_state_for(item[:source])[:bonus_action] -= 1
      else
        battle.entity_state_for(item[:source])[:action] -= 1
      end
    end
  end
end

class DisengageBonusAction < DisengageAction
  def self.can?(entity, battle)
    battle && entity.class_feature?('cunning_action') && entity.total_bonus_actions(battle) > 0
  end
end
