module ItemLibrary
  # Represents a staple of DnD the concealed pit trap
  class PitTrap < Object
    include AreaTrigger

    attr_accessor :activated

    def area_trigger_handler(entity, entity_pos, is_flying)
      result = []
      return nil if entity_pos != position
      return nil if is_flying

      unless activated
        damage = Natural20::DieRoll.roll(@properties[:damage_die])
        result = [
          {
            source: self,
            type: :state,
            params: {
              activated: true
            }
          },
          {
            source: self,
            target: entity,
            type: :damage,
            attack_name: @properties[:attack_name] || 'pit trap',
            damage_type: @properties[:damage_type] || 'piercing',
            damage: damage
          }
        ]
      end

      result
    end

    def placeable?
      !activated
    end

    def label
      return 'ground' unless activated

      @properties[:name].presence || 'pit trap'
    end

    def passable?
      true
    end

    def token
      ["\u02ac"]
    end

    def concealed?
      !activated
    end

    def jump_required?
      activated
    end

    protected

    def setup_other_attributes
      @activated = false
    end
  end
end
