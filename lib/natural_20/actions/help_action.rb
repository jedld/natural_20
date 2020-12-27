class HelpAction < Action
  attr_accessor :target

  def self.can?(entity, battle)
    battle && entity.total_actions(battle).positive?
  end

  def build_map
    OpenStruct.new({
                     action: self,
                     param: [
                       {
                         type: :select_target,
                         target_types: %i[allies enemies],
                         range: 5,
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
    action = HelpAction.new(session, source, :help)
    action.build_map
  end

  def resolve(_session, _map, opts = {})
    @result = [{
      source: @source,
      target: @target,
      type: :help,
      battle: opts[:battle]
    }]
    self
  end

  def apply!(battle)
    @result.each do |item|
      case (item[:type])
      when :help
        EventManager.received_event({ source: item[:source], target: item[:target], event: :help })
        item[:source].help!(item[:battle], item[:target])
      end

      battle.entity_state_for(item[:source])[:action] -= 1
    end
  end
end
