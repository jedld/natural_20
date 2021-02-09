# typed: true
class DodgeAction < Natural20::Action
  attr_accessor :as_bonus_action

  def self.can?(entity, battle)
    battle && entity.total_actions(battle).positive?
  end

  def build_map
    OpenStruct.new({
                     param: nil,
                     next: -> { self }
                   })
  end

  def self.build(session, source)
    action = DodgeAction.new(session, source, :attack)
    action.build_map
  end

  def resolve(_session, _map, opts = {})
    @result = [{
      source: @source,
      type: :dodge,
      as_bonus: as_bonus_action,
      battle: opts[:battle]
    }]
    self
  end

  def self.apply!(battle, item)
    case (item[:type])
    when :dodge
      Natural20::EventManager.received_event({ source: item[:source], event: :dodge })
      item[:source].dodging!(battle)

      if item[:as_bonus_action]
        battle.entity_state_for(item[:source])[:bonus_action] -= 1
      else
        battle.entity_state_for(item[:source])[:action] -= 1
      end
    end
  end
end
