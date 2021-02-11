class ShortRestAction < Natural20::Action
  attr_accessor :as_bonus_action

  # @param entity [Natural20::Entity]
  # @param battle [Natural20::Battle]
  def self.can?(entity, battle)
    battle && !battle.combat? && (entity.conscious? || entity.stable?)
  end

  def build_map
    OpenStruct.new({
                     param: nil,
                     next: -> { self }
                   })
  end

  def self.build(session, source)
    action = ShortRestAction.new(session, source, :short_rest)
    action.build_map
  end

  # @option opts battle [Natural20::Battle]
  def resolve(_session, _map, opts = {})
    battle = opts[:battle]

    # determine who in the party is eligible for short rest
    entities = battle.current_party.select do |entity|
      entity.conscious? || entity.stable?
    end

    @result = [{
      source: @source,
      targets: entities,
      type: :short_rest,
      battle: battle
    }]

    self
  end

  # @param battle [Natural20::Battle]
  def self.apply!(battle, item)
    case (item[:type])
    when :short_rest
      Natural20::EventManager.received_event({ source: item[:source], event: :short_rest, targets: item[:targets] })
      item[:targets].each do |entity|
        entity.short_rest!(battle, prompt: true)
      end
      battle.session.increment_game_time!(60 * 60) # increment by an hour
    end
  end
end
