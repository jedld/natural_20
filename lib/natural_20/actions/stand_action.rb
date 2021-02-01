# typed: true
class StandAction < Natural20::Action
  attr_accessor :as_bonus_action

  # @param entity [Natural20::Entity]
  # @param battle [Natural20::Battle]
  def self.can?(entity, battle)
    battle && entity.prone? && entity.speed.positive? && entity.available_movement(battle) >= required_movement(entity)
  end

  def build_map
    OpenStruct.new({
                     param: nil,
                     next: -> { self }
                   })
  end

  def self.build(session, source)
    action = StandAction.new(session, source, :attack)
    action.build_map
  end

  def resolve(_session, _map, opts = {})
    @result = [{
      source: @source,
      type: :stand,
      battle: opts[:battle]
    }]
    self
  end

  def apply!(battle)
    @result.each do |item|
      case (item[:type])
      when :stand
        item[:source].stand!
        battle.entity_state_for(item[:source])[:movement] -= (item[:source].speed / 2).floor
      end
    end
  end

  # required movement available to stand
  # @param entity [Natural20::Entity]
  def self.required_movement(entity)
    (entity.speed / 2).floor
  end
end
