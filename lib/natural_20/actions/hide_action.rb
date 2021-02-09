class HideAction < Natural20::Action
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
    action = HideAction.new(session, source, :attack)
    action.build_map
  end

  def resolve(_session, _map, opts = {})
    stealth_roll = @source.stealth_check!(opts[:battle])
    @result = [{
      source: @source,
      bonus_action: as_bonus_action,
      type: :hide,
      roll: stealth_roll,
      battle: opts[:battle]
    }]
    self
  end

  # @param battle [Natural20::Battle]
  def self.apply!(battle, item)
    case (item[:type])
    when :hide
      Natural20::EventManager.received_event({ source: item[:source], roll: item[:roll], event: :hide })
      item[:source].hiding!(battle, item[:roll].result)
      if item[:bonus_action]
        battle.consume(item[:source], :bonus_action)
      else
        battle.consume(item[:source], :action)
      end
    end
  end
end

class HideBonusAction < HideAction
  def self.can?(entity, battle)
    battle && entity.any_class_feature?(%w[cunning_action
                                           nimble_escape]) && entity.total_bonus_actions(battle).positive?
  end
end
