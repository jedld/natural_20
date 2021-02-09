class EscapeGrappleAction < Natural20::Action
  attr_accessor :target

  def self.can?(entity, battle, _options = {})
    entity.grappled? && (battle.nil? || entity.total_actions(battle).positive?)
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
                         targets: @source.grapples,
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
    action = EscapeGrappleAction.new(session, source, :escape_grapple)
    action.build_map
  end

  # Build the attack roll information
  # @param session [Natural20::Session]
  # @param map [Natural20::BattleMap]
  # @option opts battle [Natural20::Battle]
  # @option opts target [Natural20::Entity]
  def resolve(_session, _map, opts = {})
    battle = opts[:battle]
    target = @source.grapples.first

    strength_roll = target.athletics_check!(battle)
    athletics_stats = (@source.athletics_proficient? ? @source.proficiency_bonus : 0) + @source.str_mod
    acrobatics_stats = (@source.acrobatics_proficient? ? @source.proficiency_bonus : 0) + @source.dex_mod

    contested_roll = athletics_stats > acrobatics_stats ? @source.athletics_check!(battle) : @source.acrobatics_check!(battle)
    grapple_success = strength_roll.result >= contested_roll.result

    @result = if grapple_success
                [{
                  source: @source,
                  target: target,
                  type: :grapple_escape,
                  success: true,
                  battle: battle,
                  source_roll: contested_roll,
                  target_roll: strength_roll
                }]
              else
                [{
                  source: @source,
                  target: target,
                  type: :grapple_escape,
                  success: false,
                  battle: battle,
                  source_roll: contested_roll,
                  target_roll: strength_roll
                }]
              end
  end

  def self.apply!(battle, item)
    case (item[:type])
    when :grapple_escape
      if item[:success]
        item[:source].escape_grapple_from!(item[:target])
        Natural20::EventManager.received_event(event: :escape_grapple_success,
                                               target: item[:target], source: item[:source],
                                               source_roll: item[:source_roll],
                                               target_roll: item[:target_roll])
      else
        Natural20::EventManager.received_event(event: :escape_grapple_failure,
                                               target: item[:target], source: item[:source],
                                               source_roll: item[:source_roll],
                                               target_roll: item[:target_roll])
      end

      battle.consume(item[:source], :action)
    end
  end
end
