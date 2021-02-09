class ShoveAction < Natural20::Action
  include Natural20::ActionDamage
  attr_accessor :target, :knock_prone

  def self.can?(entity, battle, _options = {})
    (battle.nil? || entity.total_actions(battle).positive?)
  end

  def validate
    @errors << 'target is a required option for :attack' if target.nil?
    @errors << t('validation.shove.invalid_target_size') if (target.size_identifier - @source.size_identifier) > 1
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
                         target_types: %i[enemies],
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
    action = ShoveAction.new(session, source, :shove)
    action.build_map
  end

  # Build the attack roll information
  # @param session [Natural20::Session]
  # @param map [Natural20::BattleMap]
  # @option opts battle [Natural20::Battle]
  # @option opts target [Natural20::Entity]
  def resolve(_session, map, opts = {})
    target = opts[:target] || @target
    battle = opts[:battle]
    raise 'target is a required option for :attack' if target.nil?

    return if (target.size_identifier - @source.size_identifier) > 1

    strength_roll = @source.athletics_check!(battle)
    athletics_stats = (@target.athletics_proficient? ? @target.proficiency_bonus : 0) + @target.str_mod
    acrobatics_stats = (@target.acrobatics_proficient? ? @target.proficiency_bonus : 0) + @target.dex_mod

    shove_success = false
    if @target.incapacitated?
      shove_success = true
    else
      contested_roll = if athletics_stats > acrobatics_stats
                         @target.athletics_check!(battle,
                                                  description: t('die_roll.contest'))
                       else
                         @target.acrobatics_check!(
                           opts[:battle], description: t('die_roll.contest')
                         )
                       end
      shove_success = strength_roll.result >= contested_roll.result
    end

    shove_loc = nil
    additional_effects = []
    unless knock_prone
      shove_loc = @target.push_from(map, *map.entity_or_object_pos(@source))
      if shove_loc
        trigger_results = map.area_trigger!(@target, shove_loc, false)
        additional_effects += trigger_results
      end
    end
    @result = if shove_success
                [{
                  source: @source,
                  target: target,
                  type: :shove,
                  success: true,
                  battle: battle,
                  shove_loc: shove_loc,
                  knock_prone: knock_prone,
                  source_roll: strength_roll,
                  target_roll: contested_roll
                }] + additional_effects
              else
                [{
                  source: @source,
                  target: target,
                  type: :shove,
                  success: false,
                  battle: battle,
                  knock_prone: knock_prone,
                  source_roll: strength_roll,
                  target_roll: contested_roll
                }]
              end
  end

  def self.apply!(battle, item)
    case (item[:type])
    when :shove
      if item[:success]
        if item[:knock_prone]
          item[:target].prone!
        elsif item[:shove_loc]
          item[:battle].map.move_to!(item[:target], *item[:shove_loc], battle)
        end

        Natural20::EventManager.received_event(event: :shove_success,
                                               knock_prone: item[:knock_prone],
                                               target: item[:target], source: item[:source],
                                               source_roll: item[:source_roll],
                                               target_roll: item[:target_roll])
      else
        Natural20::EventManager.received_event(event: :shove_failure,
                                               target: item[:target], source: item[:source],
                                               source_roll: item[:source_roll],
                                               target_roll: item[:target_roll])
      end

      battle.entity_state_for(item[:source])[:action] -= 1
    end
  end
end

class PushAction < ShoveAction
end
