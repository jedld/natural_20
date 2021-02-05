class LookAction < Natural20::Action
  attr_accessor :ui_callback

  # @param entity [Natural20::Entity]
  # @param battle [Natural20::Battle]
  def self.can?(entity, battle)
    battle.nil? || !battle.ongoing? || battle.entity_state_for(entity)[:active_perception].zero?
  end

  def build_map
    OpenStruct.new({
                     param: [
                       {
                         type: :look,
                         num: 1
                       }
                     ],
                     next: lambda { |callback|
                       self.ui_callback = callback
                       OpenStruct.new({
                                        param: nil,
                                        next: -> { self }
                                      })
                     }
                   })
  end

  def self.build(session, source)
    action = LookAction.new(session, source, :look)
    action.build_map
  end

  def resolve(_session, _map, opts = {})
    perception_check = @source.perception_check!(opts[:battle])
    perception_check_2 = @source.perception_check!(opts[:battle])

    perception_check_disadvantage = [perception_check, perception_check_2].min
    @result = [{
      source: @source,
      type: :look,
      die_roll: perception_check,
      die_roll_disadvantage: perception_check_disadvantage,
      battle: opts[:battle]
    }]
    self
  end

  def apply!(battle)
    @result.each do |item|
      case (item[:type])
      when :look
        battle.entity_state_for(item[:source])[:active_perception] = item[:die_roll].result
        battle.entity_state_for(item[:source])[:active_perception_disadvantage] = item[:die_roll_disadvantage].result
        Natural20::EventManager.received_event({
                                                 source: item[:source],
                                                 perception_roll: item[:die_roll],
                                                 event: :perception
                                               })
        ui_callback&.target_ui(item[:source], perception: item[:die_roll].result, look_mode: true)
      end
    end
  end
end
