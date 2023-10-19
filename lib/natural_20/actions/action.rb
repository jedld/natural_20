# typed: true
module Natural20
  class Action
    attr_reader :action_type, :result, :source, :session, :errors, :opts

    def initialize(session, source, action_type, opts = {})
      @source = source
      @session = session
      @action_type = action_type
      @errors = []
      @result = []
      @opts = opts
    end

    # @param entity [Natural20::Entity]
    # @param battle [Natural20::Battle]
    # @return [Boolean]
    def self.can?(entity, battle, options = {})
      false
    end

    def name
      @action_type.to_s
    end

    def to_s
      @action_type.to_s.humanize
    end

    def to_h
      {
        action_type: @action_type,
        source: @source.entity_uid
      }
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
