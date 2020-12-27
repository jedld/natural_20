class Action
  attr_reader :action_type, :result, :source

  def initialize(session, source, action_type, opts = {})
    @source = source
    @session = session
    @action_type = action_type
    @result = []
    @opts = opts
  end

  def name
    @action_type.to_s
  end

  def to_s
    @action_type.to_s.humanize
  end

  def label
    action_type.to_s.humanize
  end

  def apply!(battle); end

  def resolve(session, map, opts = {}); end
end
