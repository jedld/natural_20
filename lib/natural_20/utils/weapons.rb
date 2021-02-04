# reusable utility methods for weapon calculations
module Natural20::Weapons
  # Check all the factors that affect advantage/disadvantage in attack rolls
  def target_advantage_condition(battle, source, target, weapon, source_pos: nil)
    advantages, disadvantages = compute_advantages_and_disadvantages(battle, source, target, weapon,
                                                                     source_pos: source_pos)

    return [0, [advantages, disadvantages]] if advantages.empty? && disadvantages.empty?
    return [0, [advantages, disadvantages]] if !advantages.empty? && !disadvantages.empty?

    return [1, [advantages, disadvantages]] unless advantages.empty?

    [-1, [advantages, disadvantages]]
  end

  # Compute all advantages and disadvantages
  # @param battle [Natural20::Battle]
  # @param source [Natural20::Entity]
  # @param target [Natural20::Entity]
  # @option weapon type [String]
  # @return [Array]
  def compute_advantages_and_disadvantages(battle, source, target, weapon, source_pos: nil)
    advantage = []
    disadvantage = []

    disadvantage << :prone if source.prone?
    disadvantage << :squeezed if source.squeezed?
    disadvantage << :target_dodge if target.dodge?(battle)
    disadvantage << :armor_proficiency unless source.proficient_with_equipped_armor?
    advantage << :squeezed if target.squeezed?
    advantage << :being_helped if battle.help_with?(target)
    disadvantage << :target_long_range if battle.map && battle.map.distance(source, target,
                                                                            entity_1_pos: source_pos) > weapon[:range]

    if weapon[:type] == 'ranged_attack' && battle.map
      disadvantage << :ranged_with_enemy_in_melee if battle.enemy_in_melee_range?(source, source_pos: source_pos)
      disadvantage << :target_is_prone_range if target.prone?
    end

    if source.class_feature?('pack_tactics') && battle.ally_within_enemey_melee_range?(source, target,
                                                                                       source_pos: source_pos)
      advantage << :pack_tactics
    end

    disadvantage << :small_creature_using_heavy if weapon[:properties]&.include?('heavy') && source.size == :small
    advantage << :target_is_prone if weapon[:type] == 'melee_attack' && target.prone?

    advantage << :unseen_attacker if battle.map && !battle.can_see?(target, source, entity_1_pos: source_pos)
    [advantage, disadvantage]
  end

  # Calculates weapon damage roll
  # @param entity [Natural20::Entity]
  # @param weapon [Hash] weapon descriptor
  # @param second_hand [Boolran] Second hand to be used for two weapon fighting
  # @return [String]
  def damage_modifier(entity, weapon, second_hand: false)
    damage_mod = entity.attack_ability_mod(weapon)

    damage_mod = [damage_mod, 0].min if second_hand && !entity.class_feature?('two_weapon_fighting')

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
