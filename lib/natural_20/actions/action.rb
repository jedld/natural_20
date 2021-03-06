# typed: true
module Natural20
  class Action
    attr_reader :action_type, :result, :source, :session, :errors

    def initialize(session, source, action_type, opts = {})
      @source = source
      @session = session
      @action_type = action_type
      @errors = []
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
      I18n.t(:"action.#{action_type}")
    end

    def validate
    end

    def self.apply!(battle, item); end

    def resolve(session, map, opts = {}); end

    protected

    def t(k, options = {})
      I18n.t(k, **options)
    end
  end
end
