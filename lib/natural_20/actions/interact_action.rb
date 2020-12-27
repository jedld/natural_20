class InteractAction < Action
  attr_accessor :target, :object_action

  def self.can?(entity, battle)
    battle.nil? || entity.total_actions(battle).positive? || entity.free_object_interaction?(battle)
  end

  def self.build(session, source)
    action = InteractAction.new(session, source, :attack)
    action.build_map
  end

  def build_map
    OpenStruct.new({
                     action: self,
                     param: [
                       {
                         type: :select_object
                       }
                     ],
                     next: lambda { |object|
                             self.target = object
                             OpenStruct.new({
                                              param: [
                                                {
                                                  type: :interact,
                                                  target: object
                                                }
                                              ],
                                              next: lambda { |action|
                                                      self.object_action = action
                                                      OpenStruct.new({
                                                                       param: nil,
                                                                       next: lambda {
                                                                               self
                                                                             }
                                                                     })
                                                    }

                                            })
                           }
                   })
  end

  def resolve(_session, map = nil, opts = {})
    battle = opts[:battle]

    result = target.resolve(@source, object_action)

    return [] if result.nil?

    result_payload = {
      source: @source,
      target: target,
      object_action: object_action,
      map: map,
      battle: battle,
      type: :interact
    }.merge(result)
    @result = [result_payload]
    self
  end

  def apply!(battle)
    @result.each do |item|
      entity = item[:source]
      case (item[:type])
      when :interact
        EventManager.received_event({ event: :interact, source: entity, target: item[:target],
                                      object_action: item[:object_action] })
        item[:target].use!(entity, item)
        if item[:cost] == :action
          battle&.consume!(entity, :action, 1)
        else
          battle&.consume!(entity, :free_object_interaction, 1) || battle&.consume!(entity, :action, 1)
        end
      end
    end
  end
end
