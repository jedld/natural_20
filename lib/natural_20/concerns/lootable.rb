module Natural20::Lootable
  include Natural20::Container

  # Builds a custom UI map
  # @param action [Symbol] The item specific action
  # @param action_object [InteractAction]
  # @return [OpenStruct]
  def build_map(action, action_object)
    case action
    when :give
      OpenStruct.new({
                       action: action_object,
                       param: [
                         {
                           type: :select_items,
                           label: action_object.source.items_label,
                           items: action_object.source.inventory
                         }
                       ],
                       next: lambda { |items|
                               action_object.other_params = items
                               OpenStruct.new({
                                                param: nil,
                                                next: lambda {
                                                        action_object
                                                      }
                                              })
                             }
                     })
    when :loot
      OpenStruct.new({
                       action: action_object,
                       param: [
                         {
                           type: :select_items,
                           label: items_label,
                           items: inventory + equipped_items
                         }
                       ],
                       next: lambda { |items|
                               action_object.other_params = items
                               OpenStruct.new({
                                                param: nil,
                                                next: lambda {
                                                        action_object
                                                      }
                                              })
                             }
                     })
    end
  end

  # Lists default available interactions for an entity
  # @param entity [Natural20::Entity]
  # @param battle [Natural20::Battle]
  # @return [Array] List of availabel actions
  def available_interactions(entity, battle = nil)
    other_interactions = super entity, battle
    other_interactions << :give if !npc? || object?
    # other_interactions << :pickpocket if !unconscious && npc?
    other_interactions << :loot if (dead? || unconscious? || opened?) && inventory_count.positive?

    other_interactions
  end

  def interactable?
    true
  end

  # @param entity [Natural20::Entity]
  # @param action [InteractAction]
  # @param other_params [Hash]
  def resolve(entity, action, other_params, opts = {})
    return if action.nil?

    case action
    when :give, :loot
      { action: action, items: other_params, source: entity, target: self, battle: opts[:battle] }
    end
  end

  # @param entity [Natural20::Entity]
  # @option result action [Symbol]
  # @option result items [Array]
  # @option result source [Natural20::Entity]
  def use!(_entity, result)
    case (result[:action])
    when :give
      store(result[:battle], result[:source], result[:target], result[:items])
    when :loot
      retrieve(result[:battle], result[:source], result[:target], result[:items])
    end
  end
end
