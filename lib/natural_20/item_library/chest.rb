# typed: false
module ItemLibrary
  class Chest < Object
    include Natural20::Container

    attr_reader :state, :locked, :key_name

    # Builds a custom UI map
    # @param action [Symbol] The item specific action
    # @param action_object [InteractAction]
    # @return [OpenStruct]
    def build_map(action, action_object)
      case action
      when :store
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

    def unlock!
      @locked = false
    end

    def lock!
      @locked = true
    end

    def locked?
      @locked
    end

    def passable?
      true
    end

    def closed?
      @state == :closed
    end

    def opened?
      @state == :opened
    end

    def open!
      @state = :opened
    end

    def close!
      @state = :closed
    end

    def token
      return '`' if dead?

      t = opened? ? "\u2610" : "\u2610"
      [t]
    end

    def color
      opened? ? :white : super
    end

    # Returns available interaction with this object
    # @param entity [Natural20::PlayerCharacter]
    # @return [Array]
    def available_interactions(entity, battle = nil)
      interaction_actions = {}
      if locked?
        interaction_actions[:unlock] = { disabled: !entity.item_count(:"#{key_name}").positive?,
                                         disabled_text: t('object.door.key_required') }
        if entity.item_count('thieves_tools').positive? && entity.proficient?('thieves_tools')
          interaction_actions[:lockpick] =
            { disabled: !entity.action?(battle), disabled_text: t('object.door.action_required') }
        end
        return interaction_actions
      end

      if opened?
        %i[close store loot]
      else
        { open: {}, lock: { disabled: !entity.item_count(:"#{key_name}").positive?,
                            disabled_text: t('object.door.key_required') } }
      end
    end

    def interactable?
      true
    end

    # @param entity [Natural20::Entity]
    # @param action [InteractAction]
    def resolve(entity, action, other_params, opts = {})
      return if action.nil?

      case action
      when :open
        if !locked?
          {
            action: action
          }
        else
          {
            action: :door_locked
          }
        end
      when :loot, :store
        { action: action, items: other_params, source: entity, target: self, battle: opts[:battle] }
      when :close
        {
          action: action
        }
      when :lockpick
        lock_pick_roll = entity.lockpick!(opts[:battle])

        if lock_pick_roll.result >= lockpick_dc
          { action: :lockpick_success, roll: lock_pick_roll, cost: :action }
        else
          { action: :lockpick_fail, roll: lock_pick_roll, cost: :action }
        end
      when :unlock
        entity.item_count(:"#{key_name}").positive? ? { action: :unlock } : { action: :unlock_failed }
      when :lock
        entity.item_count(:"#{key_name}").positive? ? { action: :lock } : { action: :lock_failed }
      end
    end

    # @param entity [Natural20::Entity]
    # @param result [Hash]
    def use!(entity, result)
      case result[:action]
      when :store
        store(result[:battle], result[:source], result[:target], result[:items])
      when :loot
        retrieve(result[:battle], result[:source], result[:target], result[:items])
      when :open
        open! if closed?
      when :close
        return unless opened?

        close!
      when :lockpick_success
        return unless locked?

        unlock!
        Natural20::EventManager.received_event(source: self, user: entity, event: :object_interaction,
                                               sub_type: :unlock, result: :success, lockpick: true, roll: result[:roll], reason: t(:"object.chest.unlock"))
      when :lockpick_fail
        return unless locked?

        entity.deduct_item('thieves_tools')
        Natural20::EventManager.received_event(source: self, user: entity, event: :object_interaction,
                                               sub_type: :unlock, result: :failed, roll: result[:roll], reason: t('object.lockpick_failed'))

      when :unlock
        return unless locked?

        unlock!
        Natural20::EventManager.received_event(source: self, user: entity, event: :object_interaction,
                                               sub_type: :unlock, result: :success, reason: t(:"object.chest.unlock"))
      when :lock
        return unless unlocked?

        lock!
        Natural20::EventManager.received_event(source: self, user: entity, event: :object_interaction,
                                               sub_type: :lock, result: :success, reason: t(:"object.chest.lock"))
      when :door_locked
        Natural20::EventManager.received_event(source: self, user: entity, event: :object_interaction,
                                               sub_type: :open_failed, result: :failed, reason: 'Cannot open chest since chest is locked.')
      when :unlock_failed
        Natural20::EventManager.received_event(source: self, user: entity, event: :object_interaction,
                                               sub_type: :unlock_failed, result: :failed, reason: 'Correct Key missing.')
      end
    end

    def lockpick_dc
      (@properties[:lockpick_dc].presence || 10)
    end

    protected

    def on_take_damage(battle, damage_params); end

    def setup_other_attributes
      @state = @properties[:state]&.to_sym || :closed
      @locked = @properties[:locked]
      @key_name = @properties[:key]
    end
  end
end
