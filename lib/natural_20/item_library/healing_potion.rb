module ItemLibrary
  class HealingPotion < BaseItem
    def build_map(action)
      OpenStruct.new({
        param: [
          {
            type: :select_target,
            num: 1,
            range: 5,
            target_types: [:allies, :self]
          }
        ],
        next: ->(target) {
          action.target = target
          OpenStruct.new({
            param: nil,
            next: ->() {
              action
            }
          })
        }
      })
    end

    def initialize(name, properties)
      @name = name
      @properties = properties
    end

    def consumable?
      @properties[:consumable]
    end

    def resolve
      hp_regain_roll = DieRoll.roll(@properties[:hp_regained])

      {
        hp_gain_roll: hp_regain_roll
      }
    end

    def use!(entity, result)
      entity.heal!(result[:hp_gain_roll].result)
    end
  end
end
