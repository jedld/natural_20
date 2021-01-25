# typed: true
module ItemLibrary
  class HealingPotion < BaseItem
    def build_map(action)
      OpenStruct.new({
                       param: [
                         {
                           type: :select_target,
                           num: 1,
                           range: 5,
                           target_types: %i[allies self]
                         }
                       ],
                       next: lambda { |target|
                               action.target = target
                               OpenStruct.new({
                                                param: nil,
                                                next: lambda {
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

    # @param entity [Natural20::Entity]
    # @param battle [Natrual20::Battle]
    def resolve(entity, battle)
      hp_regain_roll = Natural20::DieRoll.roll(@properties[:hp_regained], description: t('dice_roll.healing_potion'),
                                                                          entity: entity,
                                                                          battle: battle)

      {
        hp_gain_roll: hp_regain_roll
      }
    end

    def use!(entity, result)
      entity.heal!(result[:hp_gain_roll].result)
    end
  end
end
