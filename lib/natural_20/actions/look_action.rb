class LookAction < Natural20::Action
  attr_accessor :ui_callback

  def self.can?(_entity, _battle)
    true
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
    action = LookAction.new(session, source, :attack)
    action.build_map
  end

  def resolve(_session, _map, opts = {})
    perception_check = @source.perception_check!(opts[:battle])
    @result = [{
      source: @source,
      type: :look,
      die_roll: perception_check,
      battle: opts[:battle]
    }]
    self
  end

  def apply!(_battle)
    @result.each do |item|
      case (item[:type])
      when :look
        Natural20::EventManager.received_event({
                                                 source: item[:source],
                                                 perception_roll: item[:die_roll],
                                                 event: :perception
                                               })
        ui_callback.target_ui(item[:source], perception: item[:die_roll].result, look_mode: true)
      end
    end
  end
end
