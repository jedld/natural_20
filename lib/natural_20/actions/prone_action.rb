# typed: true
class ProneAction < Natural20::Action
  attr_accessor :as_bonus_action

  def self.can?(entity, battle)
    battle && !entity.prone?
  end

  def build_map
    OpenStruct.new({
                     param: nil,
                     next: -> { self }
                   })
  end

  def self.build(session, source)
    action = ProneAction.new(session, source, :attack)
    action.build_map
  end

  def resolve(_session, _map, opts = {})
    @result = [{
      source: @source,
      type: :prone,
      battle: opts[:battle]
    }]
    self
  end

  def apply!(_battle)
    @result.each do |item|
      case (item[:type])
      when :prone
        item[:source].prone!
      end
    end
  end
end
