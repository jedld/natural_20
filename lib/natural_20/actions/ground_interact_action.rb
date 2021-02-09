# typed: true
class GroundInteractAction < Natural20::Action
  attr_accessor :target, :ground_items

  def self.can?(entity, battle)
    battle.nil? || (entity.total_actions(battle).positive? || entity.free_object_interaction?(battle)) && items_on_the_ground_count(entity, battle).positive?
  end

  def self.build(session, source)
    action = GroundInteractAction.new(session, source, :ground_interact)
    action.build_map
  end

  # @param entity [Natural20::Entity]
  # @param battle [Natural20::Battle]
  # @return [Integer]
  def self.items_on_the_ground_count(entity, battle)
    return 0 unless battle.map

    battle.map.items_on_the_ground(entity).inject(0) { |total, item| total + item[1].size }
  end

  def build_map
    OpenStruct.new({
                     action: self,
                     param: [
                       {
                         type: :select_ground_items
                       }
                     ],
                     next: lambda { |object|
                       self.ground_items = object

                       OpenStruct.new({
                                        param: nil,
                                        next: lambda {
                                                self
                                              }
                                      })
                     }
                   })
  end

  def resolve(_session, map = nil, opts = {})
    battle = opts[:battle]

    actions = ground_items.map do |g, items|
      [g, { action: :pickup, items: items, source: @source, target: g, battle: opts[:battle] }]
    end.to_h

    @result << {
      source: @source,
      actions: actions,
      map: map,
      battle: battle,
      type: :pickup
    }

    self
  end

  def self.apply!(battle, item)
      entity = item[:source]
      case (item[:type])
      when :pickup
        item[:actions].each do |g, action|
          g.use!(nil, action)
        end

        if item[:cost] == :action
          battle&.consume!(entity, :action, 1)
        else
          battle&.consume!(entity, :free_object_interaction, 1) || battle&.consume!(entity, :action, 1)
        end
      end
  end
end
