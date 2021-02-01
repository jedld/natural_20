module Natural20
  module EntityStateEvaluator
    # Safely evaluates a DSL to return a boolean expression
    # @param conditions [String]
    # @param context [Hash]
    # @return [Boolean]
    def eval_if(conditions, context = {})
      or_groups = conditions.split('|')
      !!or_groups.detect do |g|
        and_groups = g.split('&')
        and_groups.detect do |and_g|
          cmd, test_expression = and_g.strip.split(':')
          invert = test_expression[0] == '!'
          test_expression = test_expression[1..test_expression.size - 1] if test_expression[0] == '!'
          result = case cmd.to_sym
                   when :inventory
                     item_count(test_expression).positive?
                   when :equipped
                     equipped_items.map(&:name).include?(test_expression.to_sym)
                   when :object_type
                     context[:item_type].to_s.downcase == test_expression.to_s.downcase
                   when :target
                     (test_expression == 'object' && context[:target].object?)
                   when :entity
                     (test_expression == 'pc' && pc?) ||
                     (test_expression == 'npc' && npc?)
                   when :state
                     case test_expression
                     when 'unconscious'
                       unconscious?
                     when 'stable'
                       stable?
                     when 'dead'
                       dead?
                     when 'conscious'
                       conscious?
                     end
                   else
                     raise "Invalid expression #{cmd} #{test_expression}"
                   end

          invert ? result : !result
        end.nil?
      end
    end

    def apply_effect(expression, context = {})
      action, value = expression.split(':')
      case action
      when 'status'
        {
          source: self,
          type: value.to_sym,
          battle: context[:battle]
        }
      end
    end
  end
end
