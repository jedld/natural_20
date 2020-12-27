class SecondWindAction < Action
  def self.can?(entity, battle)
    (battle.nil? || entity.total_bonus_actions(battle).positive?) && entity.second_wind_count.positive?
  end

  def label
    "Second Wind"
  end

  def build_map
    OpenStruct.new({
      action: self,
      param: nil,
      next: ->() {self},
    })
  end

  def self.build(session, source)
    action = SecondWindAction.new(session, source, :second_wind)
    action.build_map
  end

  def resolve(session, map, opts = {})
    second_wind_roll = DieRoll.roll(@source.second_wind_die)
    @result = [{
      source: @source,
      roll: second_wind_roll,
      type: :second_wind,
      battle: opts[:battle],
    }]
    self
  end

  def apply!(battle)
    @result.each do |item|
      case (item[:type])
      when :second_wind
        EventManager.received_event(action: self.class, source: item[:source], roll: item[:roll], event: :second_wind)
        item[:source].second_wind!(item[:roll].result)
        battle.entity_state_for(item[:source])[:bonus_action] -= 1
      end
    end
  end

  def self.describe(event)
    "#{event[:source].name.colorize(:green)} uses " + "Second Wind".colorize(:blue) + " with #{event[:roll].to_s} healing"
  end
end