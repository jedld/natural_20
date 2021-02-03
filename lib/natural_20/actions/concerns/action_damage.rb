module Natural20::ActionDamage
  def damage_event(item, battle)
    Natural20::EventManager.received_event({ source: item[:source], attack_roll: item[:attack_roll], target: item[:target], event: :attacked,
                                             attack_name: item[:attack_name],
                                             damage_type: item[:damage_type],
                                             advantage_mod: item[:advantage_mod],
                                             as_reaction: item[:as_reaction],
                                             damage_roll: item[:damage],
                                             sneak_attack: item[:sneak_attack],
                                             adv_info: item[:adv_info],
                                             value: item[:damage].result + (item[:sneak_attack]&.result.presence || 0) })
    item[:target].take_damage!(item, battle)
  end
end
