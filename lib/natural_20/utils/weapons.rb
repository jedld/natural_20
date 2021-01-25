# reusable utility methods for weapon calculations
module Natural20::Weapons
  # Calculates weapon damage roll
  # @param entity [Natural20::Entity]
  # @param weapon [Hash] weapon descriptor
  # @return [String]
  def damage_modifier(entity, weapon)
    damage_mod = entity.attack_ability_mod(weapon)

    # compute damage roll using versatile weapon property
    damage_roll = if weapon[:properties]&.include?('versatile') && entity.used_hand_slots <= 1.0
                    weapon[:damage_2]
                  else
                    weapon[:damage]
                  end

    # duelist class feature
    if entity.class_feature?('dueling') && weapon[:type] == 'melee_attack' && entity.used_hand_slots(weapon_only: true) <= 1.0
      damage_mod += 2
    end

    "#{damage_roll}+#{damage_mod}"
  end
end