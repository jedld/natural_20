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
          result = case cmd.to_sym
                   when :inventory
                     item_count(test_expression).positive?
                   when :equipped
                     equipped_items.map(&:name).include?(test_expression.to_sym)
                   when :object_type
                     context[:item_type].to_s.downcase == test_expression.to_s.downcase
                   when :entity
                     (test_expression == 'pc' && pc?) ||
                     (test_expression == 'npc' && npc?)
                   else
                     raise "Invalid expression #{cmd} #{test_expression}"
                   end

          !result
        end.nil?
      end
    end
  end
end
