# typed: true
class AttackAction < Natural20::Action
  include Natural20::Cover
  include Natural20::Weapons
  include Natural20::AttackHelper
  extend Natural20::ActionDamage

  attr_accessor :target, :using, :npc_action, :as_reaction, :thrown, :second_hand
  attr_reader :advantage_mod

  # @param entity [Natural20::Entity]
  # @param battle [Natural20::Battle]
  # @return [Boolean]
  def self.can?(entity, battle, options = {})
    return entity.total_reactions(battle).positive? if battle && options[:opportunity_attack]

    battle.nil? || entity.total_actions(battle).positive? || entity.multiattack?(
      battle, options[:npc_action]
    )
  end

  def to_s
    @action_type.to_s.humanize
  end

  def label
    if @npc_action
      t('action.npc_action', name: @action_type.to_s.humanize, action_name: npc_action[:name])
    else
      weapon = session.load_weapon(@opts[:using] || @using)
      attack_mod = @source.attack_roll_mod(weapon)

      i18n_token = thrown ? 'action.attack_action_throw' : 'action.attack_action'

      t(i18n_token, name: @action_type.to_s.humanize, weapon_name: weapon[:name], mod: attack_mod >= 0 ? "+#{attack_mod}" : attack_mod,
                    dmg: damage_modifier(@source, weapon, second_hand: second_hand))
    end
  end

  def build_map
    OpenStruct.new({
                     action: self,
                     param: [
                       {
                         type: :select_target,
                         num: 1,
                         weapon: using
                       }
                     ],
                     next: lambda { |target|
                       self.target = target
                       OpenStruct.new({
                                        param: [
                                          { type: :select_weapon }
                                        ],
                                        next: lambda { |weapon|
                                                self.using = weapon
                                                OpenStruct.new({
                                                                 param: nil,
                                                                 next: -> { self }
                                                               })
                                              }
                                      })
                     }
                   })
  end

  def self.build(session, source)
    action = AttackAction.new(session, source, :attack)
    action.build_map
  end

  # @param battle [Natural20::Battle]
  def self.apply!(battle, item)
    if item[:flavor]
      Natural20::EventManager.received_event({ event: :flavor, source: item[:source], target: item[:target],
                                               text: item[:flavor] })
    end
    case (item[:type])
    when :prone
      item[:source].prone!
    when :damage
      damage_event(item, battle)
      consume_resource(battle, item)
    when :miss
      consume_resource(battle, item)
      Natural20::EventManager.received_event({ attack_roll: item[:attack_roll],
                                               attack_name: item[:attack_name],
                                               advantage_mod: item[:advantage_mod],
                                               as_reaction: !!item[:as_reaction],
                                               adv_info: item[:adv_info],
                                               source: item[:source], target: item[:target], event: :miss })
    end
  end

  # @param battle [Natural20::Battle]
  # @param item [Hash]
  def self.consume_resource(battle, item)
    # handle ammo
    item[:source].deduct_item(item[:ammo], 1) if item[:ammo]

    # hanle thrown items
    if item[:thrown]
      if item[:source].item_count(item[:weapon]).positive?
        item[:source].deduct_item(item[:weapon], 1)
      else
        item[:source].unequip(item[:weapon], transfer_inventory: false)
      end

      if item[:type] == :damage
        item[:target].add_item(item[:weapon])
      else
        ground_pos = item[:battle].map.entity_or_object_pos(item[:target])
        ground_object = item[:battle].map.objects_at(*ground_pos).detect { |o| o.is_a?(ItemLibrary::Ground) }
        ground_object&.add_item(item[:weapon])
      end
    end

    if item[:as_reaction]
      battle.consume(item[:source], :reaction)
    elsif item[:second_hand]
      battle.consume(item[:source], :bonus_action)
    else
      battle.consume(item[:source], :action)
    end

    item[:source].break_stealth!(battle)

    # handle two-weapon fighting
    weapon = battle.session.load_weapon(item[:weapon]) if item[:weapon]

    if weapon && weapon[:properties]&.include?('light') && !battle.two_weapon_attack?(item[:source]) && !item[:second_hand]
      battle.entity_state_for(item[:source])[:two_weapon] = item[:weapon]
    elsif battle.entity_state_for(item[:source])
      battle.entity_state_for(item[:source])[:two_weapon] = nil
    end

    # handle multiattacks
    if battle.entity_state_for(item[:source])
      battle.entity_state_for(item[:source])[:multiattack]&.each do |_group, attacks|
        if attacks.include?(item[:attack_name])
          attacks.delete(item[:attack_name])
          item[:source].clear_multiattack!(battle) if attacks.empty?
        end
      end
    end

    # dismiss help actions
    battle.dismiss_help_for(item[:target])
  end

  def with_advantage?
    @advantage_mod.positive?
  end

  def with_disadvantage?
    @advantage_mod.negative?
  end

  def compute_hit_probability(battle, opts = {})
    weapon, _, attack_mod, _, _ = get_weapon_info(opts)
    advantage_mod, adv_info = target_advantage_condition(battle, @source, target, weapon)
    target_ac, _cover_ac = effective_ac(battle, target)
    Natural20::DieRoll.roll("1d20+#{attack_mod}", advantage: advantage_mod > 0, disadvantage: advantage_mod < 0).prob(target_ac)
  end

  def avg_damage(battle, opts = {})
    _, _, _, damage_roll, _ = get_weapon_info(opts)
    Natural20::DieRoll.roll(damage_roll).expected
  end

  # Build the attack roll information
  # @param session [Natural20::Session]
  # @param map [Natural20::BattleMap]
  # @option opts battle [Natural20::Battle]
  # @option opts target [Natural20::Entity]
  def resolve(_session, map, opts = {})
    @result.clear
    battle = opts[:battle]
    target = opts[:target] || @target
    raise 'target is a required option for :attack' if target.nil?
    sneak_attack_roll = nil

    weapon, attack_name, attack_mod, damage_roll, ammo_type = get_weapon_info(opts)

    # DnD 5e advantage/disadvantage checks
    @advantage_mod, adv_info = target_advantage_condition(battle, @source, target, weapon)

    # determine eligibility for the 'Protection' fighting style
    evaluate_feature_protection(battle, map, target, adv_info) if map

    # perform the dice rolls
    attack_roll = Natural20::DieRoll.roll("1d20+#{attack_mod}", disadvantage: with_disadvantage?,
                                                                advantage: with_advantage?,
                                                                description: t('dice_roll.attack'), entity: @source, battle: battle)

    @source.send(:resolve_trigger, :attack_resolved, target: target)

    # handle the lucky feat
    attack_roll = attack_roll.reroll(lucky: true) if @source.class_feature?('lucky') && attack_roll.nat_1?
    target_ac, _cover_ac = effective_ac(battle, target)
    after_attack_roll_hook(battle, target, source, attack_roll, target_ac)

    if @source.class_feature?('sneak_attack') && (weapon[:properties]&.include?('finesse') || weapon[:type] == 'ranged_attack') && (with_advantage? || battle.enemy_in_melee_range?(
      target, [@source]
    ))
      sneak_attack_roll = Natural20::DieRoll.roll(@source.sneak_attack_level, crit: attack_roll.nat_20?,
                                                                              description: t('dice_roll.sneak_attack'), entity: @source, battle: battle)
    end

    damage = Natural20::DieRoll.roll(damage_roll, crit: attack_roll.nat_20?, description: t('dice_roll.damage'),
                                                  entity: @source, battle: battle)

    if @source.class_feature?('great_weapon_fighting') && (weapon[:properties]&.include?('two_handed') || (weapon[:properties]&.include?('versatile') && entity.used_hand_slots <= 1.0))
      damage.rolls.map do |roll|
        if [1, 2].include?(roll)
          r = Natural20::DieRoll.roll("1d#{damage.die_sides}", description: t('dice_roll.great_weapon_fighting_reroll'),
                                                               entity: @source, battle: battle)
          Natural20::EventManager.received_event({ roll: r, prev_roll: roll,
                                                   source: item[:source], event: :great_weapon_fighting_roll })
          r.result
        else
          roll
        end
      end
    end

    # apply weapon bonus attacks
    damage = check_weapon_bonuses(battle, weapon, damage, attack_roll)

    cover_ac_adjustments = 0
    hit = if attack_roll.nat_20?
            true
          elsif attack_roll.nat_1?
            false
          else
            target_ac, cover_ac_adjustments = effective_ac(battle, target)
            attack_roll.result >= target_ac
          end

    if hit
      @result << {
        source: @source,
        target: target,
        type: :damage,
        thrown: thrown,
        weapon: using,
        battle: battle,
        advantage_mod: @advantage_mod,
        damage_roll: damage_roll,
        attack_name: attack_name,
        attack_roll: attack_roll,
        sneak_attack: sneak_attack_roll,
        target_ac: target.armor_class,
        cover_ac: cover_ac_adjustments,
        adv_info: adv_info,
        hit?: hit,
        damage_type: weapon[:damage_type],
        damage: damage,
        ammo: ammo_type,
        as_reaction: !!as_reaction,
        second_hand: second_hand,
        npc_action: npc_action
      }
      unless weapon[:on_hit].blank?
        weapon[:on_hit].each do |effect|
          next if effect[:if] && !@source.eval_if(effect[:if], weapon: weapon, target: target)

          if effect[:save_dc]
            save_type, dc = effect[:save_dc].split(':')
            raise 'invalid values: save_dc should be of the form <save>:<dc>' if save_type.blank? || dc.blank?
            raise 'invalid save type' unless Natural20::Entity::ATTRIBUTE_TYPES.include?(save_type)

            save_roll = target.saving_throw!(save_type, battle: battle)
            if save_roll.result >= dc.to_i
              if effect[:success]
                @result << target.apply_effect(effect[:success], battle: battle,
                                                                 flavor: effect[:flavor_success])
              end
            elsif effect[:fail]
              @result << target.apply_effect(effect[:fail], battle: battle, flavor: effect[:flavor_fail])
            end
          else
            target.apply_effect(effect[:effect])
          end
        end
      end
    else
      @result << {
        attack_name: attack_name,
        source: @source,
        target: target,
        weapon: using,
        battle: battle,
        thrown: thrown,
        type: :miss,
        advantage_mod: @advantage_mod,
        adv_info: adv_info,
        second_hand: second_hand,
        damage_roll: damage_roll,
        attack_roll: attack_roll,
        as_reaction: !!as_reaction,
        target_ac: target.armor_class,
        cover_ac: cover_ac_adjustments,
        ammo: ammo_type,
        npc_action: npc_action
      }
    end

    self
  end


  def get_weapon_info(opts)
    target = opts[:target] || @target
    raise 'target is a required option for :attack' if target.nil?

    npc_action = opts[:npc_action] || @npc_action

    using = opts[:using] || @using
    raise 'using or npc_action is a required option for :attack' if using.nil? && npc_action.nil?

    attack_name = nil
    damage_roll = nil
    ammo_type = nil

    npc_action = @source.npc_actions.detect { |a| a[:name].downcase == using.downcase } if @source.npc? && using

    if @source.npc?
      if npc_action.nil?
        npc_action = @source.properties[actions].detect do |action|
          action[:name].downcase == using.to_s.downcase
        end
      end
      weapon = npc_action
      attack_name = npc_action[:name]
      attack_mod = npc_action[:attack]
      damage_roll = npc_action[:damage_die]
      ammo_type = npc_action[:ammo]
    else
      weapon = session.load_weapon(using.to_sym)
      attack_name = weapon[:name]
      ammo_type = weapon[:ammo]
      attack_mod = @source.attack_roll_mod(weapon)
      damage_roll = damage_modifier(@source, weapon, second_hand: second_hand)
    end

    [weapon, attack_name, attack_mod, damage_roll, ammo_type]
  end

  protected

  # determine eligibility for the 'Protection' fighting style
  def evaluate_feature_protection(battle, map, target, adv_info)
    melee_sqaures = target.melee_squares(map, adjacent_only: true)
    melee_sqaures.each do |pos|
      entity = map.entity_at(*pos)
      next if entity == @source
      next if entity == target
      next unless entity

      next unless entity.class_feature?('protection') && entity.shield_equipped? && entity.has_reaction?(battle)

      controller = battle.controller_for(entity)
      if controller.respond_to?(:reaction) && !controller.reaction(:feature_protection, target: target,
                                                                                        source: entity, attacker: @source)
        next
      end

      Natural20::EventManager.received_event(event: :feature_protection, target: target, source: entity,
                                             attacker: @source)
      _advantage, disadvantage = adv_info
      disadvantage << :protection
      @advantage_mod = -1
      battle.consume(entity, :reaction)
    end
  end

  def check_weapon_bonuses(battle, weapon, damage_roll, attack_roll)
    if weapon.dig(:bonus, :additional, :restriction) == 'nat20_attack' && attack_roll.nat_20?
      damage_roll += Natural20::DieRoll.roll(weapon.dig(:bonus, :additional, :die),
                                             description: t('dice_roll.special_weapon_damage'), entity: @source, battle: battle)
    end

    damage_roll
  end
end

class TwoWeaponAttackAction < AttackAction
  # @param entity [Natural20::Entity]
  # @param battle [Natural20::Battle]
  def self.can?(entity, battle, options = {})
    battle.nil? || (entity.total_bonus_actions(battle).positive? && battle.two_weapon_attack?(entity) && (options[:weapon] != battle.first_hand_weapon(entity) || entity.equipped_weapons.select do |a|
      a.to_s == battle.first_hand_weapon(entity)
    end.size >= 2))
  end

  def second_hand
    true
  end

  def label
    "Bonus Action -> #{super}"
  end

  def self.apply!(battle, item); end
end
