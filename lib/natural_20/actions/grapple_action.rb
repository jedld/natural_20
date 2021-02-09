class GrappleAction < Natural20::Action
  attr_accessor :target

  def self.can?(entity, battle, _options = {})
    (battle.nil? || entity.total_actions(battle).positive?) && !entity.grappling?
  end

  def to_s
    @action_type.to_s.humanize
  end

  def validate
    @errors << 'target is a required option for :attack' if target.nil?
    @errors << t('validation.shove.invalid_target_size') if (target.size_identifier - @source.size_identifier) > 1
  end

  def build_map
    OpenStruct.new({
                     action: self,
                     param: [
                       {
                         type: :select_target,
                         range: 5,
                         target_types: %i[enemies allies],
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
    action = GrappleAction.new(session, source, :grapple)
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
    raise 'target is a required option for :attack' if target.nil?

    return if (target.size_identifier - @source.size_identifier) > 1

    strength_roll = @source.athletics_check!(battle)
    athletics_stats = (@target.athletics_proficient? ? @target.proficiency_bonus : 0) + @target.str_mod
    acrobatics_stats = (@target.acrobatics_proficient? ? @target.proficiency_bonus : 0) + @target.dex_mod

    grapple_success = false
    if @target.incapacitated? || !battle.opposing?(@source, target)
      grapple_success = true
    else
      contested_roll = if athletics_stats > acrobatics_stats
                         @target.athletics_check!(battle,
                                                  description: t('die_roll.contest'))
                       else
                         @target.acrobatics_check!(
                           opts[:battle], description: t('die_roll.contest')
                         )
                       end
      grapple_success = strength_roll.result >= contested_roll.result
    end

    @result = if grapple_success
                [{
                  source: @source,
                  target: target,
                  type: :grapple,
                  success: true,
                  battle: battle,
                  source_roll: strength_roll,
                  target_roll: contested_roll
                }]
              else
                [{
                  source: @source,
                  target: target,
                  type: :grapple,
                  success: false,
                  battle: battle,
                  source_roll: strength_roll,
                  target_roll: contested_roll
                }]
              end
  end

  def self.apply!(battle, item)
    case (item[:type])
    when :grapple
      if item[:success]
        item[:target].grappled_by!(item[:source])
        Natural20::EventManager.received_event(event: :grapple_success,
                                               target: item[:target], source: item[:source],
                                               source_roll: item[:source_roll],
                                               target_roll: item[:target_roll])
      else
        Natural20::EventManager.received_event(event: :grapple_failure,
                                               target: item[:target], source: item[:source],
                                               source_roll: item[:source_roll],
                                               target_roll: item[:target_roll])
      end

      battle.consume(item[:source], :action)
    end
  end
end

class DropGrappleAction < Natural20::Action
  attr_accessor :target

  def self.can?(entity, battle, _options = {})
    battle.nil? || entity.grappling?
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
                         targets: @source.grappling_targets,
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
    action = DropGrappleAction.new(session, source, :grapple)
    action.build_map
  end

  # @param session [Natural20::Session]
  # @param map [Natural20::BattleMap]
  # @option opts battle [Natural20::Battle]
  # @option opts target [Natural20::Entity]
  def resolve(_session, _map, opts = {})
    target = opts[:target] || @target
    battle = opts[:battle]
    @result =
      [{
        source: @source,
        target: target,
        type: :drop_grapple,
        battle: battle
      }]
  end

  def self.apply!(_battle, item)
    case item[:type]
    when :drop_grapple
      item[:target].escape_grapple_from!(item[:source])
      Natural20::EventManager.received_event(event: :drop_grapple,
                                             target: item[:target], source: item[:source],
                                             source_roll: item[:source_roll],
                                             target_roll: item[:target_roll])

    end
  end
end
