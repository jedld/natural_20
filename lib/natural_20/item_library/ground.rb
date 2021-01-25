# typed: false
module ItemLibrary
  class Ground < Object
    include Natural20::Container

    attr_reader :state, :locked, :key_name

    # Builds a custom UI map
    # @param action [Symbol] The item specific action
    # @param action_object [InteractAction]
    # @return [OpenStruct]
    def build_map(action, action_object)
      case action
      when :drop
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
      when :pickup
        OpenStruct.new({
                         action: action_object,
                         param: [
                           {
                             type: :select_items,
                             label: items_label,
                             items: inventory
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

    def opaque?
      false
    end

    def passable?
      true
    end

    def placeable?
      true
    end

    def token
      ["\u00B7".encode('utf-8')]
    end

    def color
      :cyan
    end

    # Returns available interaction with this object
    # @param entity [Natural20::PlayerCharacter]
    # @return [Array]
    def available_interactions(_entity, _battle = nil)
      []
    end

    def interactable?
      false
    end

    # @param entity [Natural20::Entity]
    # @param action [InteractAction]
    def resolve(entity, action, other_params, opts = {})
      return if action.nil?

      case action
      when :drop, :pickup
        { action: action, items: other_params, source: entity, target: self, battle: opts[:battle] }
      end
    end

    # @param entity [Natural20::Entity]
    # @param result [Hash]
    def use!(_entity, result)
      case result[:action]
      when :drop
        store(result[:battle], result[:source], result[:target], result[:items])
      when :pickup
        retrieve(result[:battle], result[:source], result[:target], result[:items])
      end
    end

    def list_notes(_entity, _perception, highlight: false)
      inventory.map do |_item|
        t("object.#{m.label}", default: m.label)
      end
    end

    protected

    def on_take_damage(battle, damage_params); end

    def setup_other_attributes
      @inventory = {}
    end
  end
end
