module Multiattack
  def setup_attributes
    super
  end

  # Get available multiattack actions
  # @param session [Session]
  # @param battle [Battle]
  # @return [Array]
  def multi_attack_actions(session, battle)
  end

  # @param battle [Battle]
  def reset_turn!(battle)
    entity_state = super battle

    return entity_state unless class_feature?('multiattack')

    multiattack_groups = {}
    @properties[:actions].select { |a| a[:multiattack_group] }.each do |a|
      multiattack_groups[a[:multiattack_group]] ||= []
      multiattack_groups[a[:multiattack_group]] << a[:name]
    end

    entity_state[:multiattack] = multiattack_groups

    entity_state
  end

  # @param battle [Battle]
  def clear_multiattack!(battle)
    entity_state = battle.entity_state_for(self)
    entity_state[:multiattack] = {}
  end

  # @param battle [Battle]
  # @param npc_action [Hash]
  def multiattack?(battle, npc_action)
    return false unless npc_action
    return false unless class_feature?('multiattack')

    entity_state = battle.entity_state_for(self)

    return false unless entity_state[:multiattack]
    return false unless npc_action[:multiattack_group]

    entity_state[:multiattack].each do |_group, attacks|
      return true if attacks.include?(npc_action[:name])
    end

    false
  end
end
