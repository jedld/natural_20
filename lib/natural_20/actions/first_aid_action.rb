class FirstAidAction < Natural20::Action
  attr_accessor :target

  def self.can?(entity, battle, _options = {})
    (battle.nil? || entity.total_actions(battle).positive?) && unconscious_targets(entity, battle).size.positive?
  end

  # @param entity [Natural20::Entity]
  # @param battle [Natural20::Battle]
  def self.unconscious_targets(entity, battle)
    adjacent_squares = entity.melee_squares(battle.map, adjacent_only: true)
    entities = []
    adjacent_squares.select do |pos|
      entity_pos = battle.map.entity_at(*pos)
      next unless entity_pos
      next if entity_pos == entity

      entities << entity_pos if entity_pos.unconscious? && !entity_pos.stable? && !entity_pos.dead?
    end
    entities
  end

  def to_s
    @action_type.to_s.humanize
  end

  def build_map
    OpenStruct.new({
                     action: self,
                     param: [
                       {
                         type: :select_target,
                         range: 5,
                         target_types: %i[enemies allies],
                         filter: 'state:unconscious & state:!stable & state:!dead',
                         num: 1
                       }
                     ],
                     next: lambda { |target|
                       self.target = target
                       OpenStruct.new({
                                        param: nil,
                                        next: -> { self }
                                      })
                     }
                   })
  end

  def self.build(session, source)
    action = FirstAidAction.new(session, source, :grapple)
    action.build_map
  end

  # Build the attack roll information
  # @param session [Natural20::Session]
  # @param map [Natural20::BattleMap]
  # @option opts battle [Natural20::Battle]
  # @option opts target [Natural20::Entity]
  def resolve(_session, _map, opts = {})
    target = opts[:target] || @target
    battle = opts[:battle]
    raise 'target is a required option for :first_aid' if target.nil?

    medicine_check = @source.medicine_check!(battle)

    @result = if medicine_check.result >= 10
                [{
                  source: @source,
                  target: target,
                  type: :first_aid,
                  success: true,
                  battle: battle,
                  roll: medicine_check
                }]
              else
                [{
                  source: @source,
                  target: target,
                  type: :first_aid,
                  success: false,
                  battle: battle,
                  roll: medicine_check
                }]
              end
  end

  def apply!(battle)
    @result.each do |item|
      case (item[:type])
      when :first_aid
        if item[:success]
          item[:target].stable!
          Natural20::EventManager.received_event(event: :first_aid,
                                                 target: item[:target], source: @source,
                                                 roll: item[:roll])
        else
          Natural20::EventManager.received_event(event: :first_aid_failure,
                                                 target: item[:target], source: @source,
                                                 roll: item[:roll])
        end

        battle.entity_state_for(item[:source])[:action] -= 1
      end
    end
  end
end
