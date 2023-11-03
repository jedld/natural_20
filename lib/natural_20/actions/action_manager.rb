module Natural20
  class Transaction
    def initialize(entity, method_name, params = [])
      @entity = entity
      @method_name = method_name.to_sym
      @params = params
    end

    def commit
      @before_state = @entity.send(@method_name, *@params)
      raise "Invalid state format #{@entity.class.to_s}##{@method_name}" unless @before_state.is_a?(OpenStruct)
      self
    end

    def rollback
      process_states(@before_state)
    end

    private

    def process_states(state)
      state.children.reverse.each do |child_state|
        process_states(child_state)
      end

      current_entity = state.entity
      state.states.each do |attr, value|
        current_entity.send("#{attr}=", value)
      end

      if state.callback
        state.callback.call()
      end
    end
  end

  class ActionManager

  end
end