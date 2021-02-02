# typed: true
class DisengageAction < Natural20::Action
  attr_accessor :as_bonus_action

  def self.can?(entity, battle)
    battle && battle.combat? && entity.total_actions(battle).positive?
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
        Natural20::EventManager.received_event({ source: item[:source], event: :disengage })
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
  # @param entity [Natural20::Entity]
  # @param battle [Natural20::Battle]
  def self.can?(entity, battle)
    battle && battle.combat? && entity.any_class_feature?(%w[cunning_action nimble_escape]) && entity.total_bonus_actions(battle) > 0
  end
end
