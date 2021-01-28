# typed: false
module ItemLibrary
  class DoorObject < Object
    attr_reader :state, :locked, :key_name

    def opaque?
      closed? && !dead?
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
      opened? || dead?
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

      pos_x, pos_y = position
      t = if map.wall?(pos_x - 1, pos_y) || map.wall?(pos_x + 1, pos_y)
            opened? ? '-' : '='
          else
            opened? ? '|' : '║'
          end

      [t]
    end

    def token_opened
      @properties[:token_open].presence || '-'
    end

    def token_closed
      @properties[:token_closed].presence || '='
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
        { close: { disabled: someone_blocking_the_doorway?, disabled_text: t('object.door.door_blocked') } }
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
    def resolve(entity, action, _other_params, opts = {})
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
      case (result[:action])
      when :open
        open! if closed?
      when :close
        return unless opened?

        if someone_blocking_the_doorway?
          return Natural20::EventManager.received_event(source: self, user: entity, event: :object_interaction,
                                                        sub_type: :close_failed, result: :failed, reason: 'Cannot close door since something is in the doorway')
        end

        close!
      when :lockpick_success
        return unless locked?

        unlock!
        Natural20::EventManager.received_event(source: self, user: entity, event: :object_interaction,
                                               sub_type: :unlock, result: :success, lockpick: true, roll: result[:roll], reason: 'Door unlocked using lockpick.')
      when :lockpick_fail
        entity.deduct_item('thieves_tools')
        Natural20::EventManager.received_event(source: self, user: entity, event: :object_interaction,
                                               sub_type: :unlock, result: :failed, roll: result[:roll], reason: 'Lockpicking failed and the theives tools are now broken')
      when :unlock
        return unless locked?

        unlock!
        Natural20::EventManager.received_event(source: self, user: entity, event: :object_interaction,
                                               sub_type: :unlock, result: :success, reason: t('object.door.unlock'))
      when :lock
        return unless unlocked?

        lock!
        Natural20::EventManager.received_event(source: self, user: entity, event: :object_interaction,
                                               sub_type: :lock, result: :success, reason: t('object.door.lock'))
      when :door_locked
        Natural20::EventManager.received_event(source: self, user: entity, event: :object_interaction,
                                               sub_type: :open_failed, result: :failed, reason: 'Cannot open door since door is locked.')
      when :unlock_failed
        Natural20::EventManager.received_event(source: self, user: entity, event: :object_interaction,
                                               sub_type: :unlock_failed, result: :failed, reason: 'Correct Key missing.')
      end
    end

    def lockpick_dc
      (@properties[:lockpick_dc].presence || 10)
    end

    protected

    def someone_blocking_the_doorway?
      !!map.entity_at(*position)
    end

    def on_take_damage(battle, damage_params); end

    def setup_other_attributes
      @state = @properties[:state]&.to_sym || :closed
      @locked = @properties[:locked]
      @key_name = @properties[:key]
    end
  end
end
