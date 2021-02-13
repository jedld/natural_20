module Natural20::ActionDamage
  def damage_event(item, battle)
    target = item[:target]
    dmg = item[:damage].is_a?(Natural20::DieRoll) ? item[:damage].result : item[:damage]
    dmg += item[:sneak_attack].result unless item[:sneak_attack].nil?

    total_damage = if target.resistant_to?(item[:damage_type])
                     (dmg / 2.to_f).floor
                   elsif target.vulnerable_to?(item[:damage_type])
                     dmg * 2
                   else
                     dmg
                   end

    item[:target].take_damage!(total_damage, battle: battle, critical: item[:attack_roll]&.nat_20?)

    item[:target].send(:on_take_damage, battle, item) if battle && total_damage.positive?

    Natural20::EventManager.received_event({ source: item[:source],
                                             attack_roll: item[:attack_roll],
                                             target: item[:target],
                                             event: :attacked,
                                             attack_name: item[:attack_name],
                                             damage_type: item[:damage_type],
                                             advantage_mod: item[:advantage_mod],
                                             as_reaction: item[:as_reaction],
                                             damage_roll: item[:damage],
                                             total_damage: total_damage,
                                             sneak_attack: item[:sneak_attack],
                                             adv_info: item[:adv_info],
                                             resistant: target.resistant_to?(item[:damage_type]),
                                             vulnerable: target.vulnerable_to?(item[:damage_type]),
                                             value: dmg,
                                             total_damage: total_damage })
  end
end
