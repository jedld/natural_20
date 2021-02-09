# typed: true
class DashAction < Natural20::Action
  attr_accessor :as_bonus_action

  def build_map
    OpenStruct.new({
                     param: nil,
                     next: -> { self }
                   })
  end

  def self.can?(entity, battle)
    battle && entity.total_actions(battle).positive?
  end

  def resolve(_session, _map, opts = {})
    @result = [{
      source: @source,
      type: :dash,
      battle: opts[:battle]
    }]
    self
  end

  def self.apply!(battle, item)
    case item[:type]
    when :dash
      Natural20::EventManager.received_event({ source: item[:source], event: :dash })
      battle.entity_state_for(item[:source])[:movement] += item[:source].speed
      if as_bonus_action
        battle.entity_state_for(item[:source])[:bonus_action] -= 1
      else
        battle.entity_state_for(item[:source])[:action] -= 1
      end
    end
  end
end

class DashBonusAction < DashAction
  def self.can?(entity, battle)
    battle && entity.class_feature?('cunning_action') && entity.total_bonus_actions(battle) > 0
  end
end
