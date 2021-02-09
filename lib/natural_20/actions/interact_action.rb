# typed: true
class InteractAction < Natural20::Action
  attr_accessor :target, :object_action, :other_params

  # @param entity [Natural20::Entity]
  # @param battle [Natural20::Battle]
  def self.can?(entity, battle)
    battle.nil? || !battle.ongoing? || entity.total_actions(battle).positive? || entity.free_object_interaction?(battle)
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

                                                custom_action = object.try(:build_map, action, self)

                                                if custom_action.nil?
                                                  OpenStruct.new({
                                                                   param: nil,
                                                                   next: lambda {
                                                                           self
                                                                         }
                                                                 })
                                                else
                                                  custom_action
                                                end
                                              }

                                      })
                     }
                   })
  end

  def resolve(_session, map = nil, opts = {})
    battle = opts[:battle]

    result = target.resolve(@source, object_action, other_params, opts)

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

  def self.apply!(battle, item)
    entity = item[:source]
    case (item[:type])
    when :interact
      item[:target].use!(entity, item)
      if item[:cost] == :action
        battle&.consume!(entity, :action, 1)
      else
        battle&.consume!(entity, :free_object_interaction, 1) || battle&.consume!(entity, :action, 1)
      end

      Natural20::EventManager.received_event(event: :interact, source: entity, target: item[:target],
                                             object_action: item[:object_action])
    end
  end
end
