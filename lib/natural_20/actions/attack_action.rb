# typed: true
class AttackAction < Natural20::Action
  include Natural20::Cover
  include Natural20::Weapons

  attr_accessor :target, :using, :npc_action, :as_reaction, :thrown, :second_hand
  attr_reader :advantage_mod

  # @param entity [Natural20::Entity]
  # @param battle [Natural20::Battle]
  # @return [Boolean]
  def self.can?(entity, battle, options = {})
    battle.nil? || entity.total_actions(battle).positive? || (options[:opportunity_attack] && entity.total_reactions(battle).positive?) || entity.multiattack?(
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

      t(i18n_token, name: @action_type.to_s.humanize, weapon_name: weapon[:name], mod: attack_mod,
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
  def apply!(battle)
    @result.each do |item|
      case (item[:type])
      when :damage
        Natural20::EventManager.received_event({ source: item[:source], attack_roll: item[:attack_roll], target: item[:target], event: :attacked,
                                                 attack_name: item[:attack_name],
                                                 damage_type: item[:damage_type],
                                                 as_reaction: as_reaction,
                                                 damage_roll: item[:damage],
                                                 sneak_attack: item[:sneak_attack],
                                                 value: item[:damage].result + (item[:sneak_attack]&.result.presence || 0) })
        item[:target].take_damage!(item, battle)
      when :miss
        Natural20::EventManager.received_event({ attack_roll: item[:attack_roll],
                                                 attack_name: item[:attack_name],
                                                 as_reaction: as_reaction,
                                                 source: item[:source], target: item[:target], event: :miss })
      end

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

      if as_reaction
        battle.entity_state_for(item[:source])[:reaction] -= 1
      elsif item[:second_hand]
        battle.entity_state_for(item[:source])[:bonus_action] -= 1
      else
        battle.entity_state_for(item[:source])[:action] -= 1
      end

      item[:source].break_stealth!(battle)

      # handle two-weapon fighting
      weapon = session.load_weapon(item[:weapon]) if item[:weapon]

      if weapon && weapon[:properties]&.include?('light') && !battle.two_weapon_attack?(item[:source]) && !item[:second_hand]
        battle.entity_state_for(item[:source])[:two_weapon] = item[:weapon]
      else
        battle.entity_state_for(item[:source])[:two_weapon] = nil
      end

      # handle multiattacks
      battle.entity_state_for(item[:source])[:multiattack]&.each do |_group, attacks|
        if attacks.include?(item[:attack_name])
          attacks.delete(item[:attack_name])
          item[:source].clear_multiattack!(battle) if attacks.empty?
        end
      end

      # dismiss help actions
      battle.dismiss_help_for(item[:target])
    end
  end

  def with_advantage?
    @advantage_mod.positive?
  end

  def with_disadvantage?
    @advantage_mod.negative?
  end

  # Build the attack roll information
  # @param session [Natural20::Session]
  # @param map [Natural20::BattleMap]
  # @option opts battle [Natural20::Battle]
  # @option opts target [Natural20::Entity]
  def resolve(_session, _map, opts = {})
    target = opts[:target] || @target
    raise 'target is a required option for :attack' if target.nil?

    npc_action = opts[:npc_action] || @npc_action
    battle = opts[:battle]
    using = opts[:using] || @using
    raise 'using or npc_action is a required option for :attack' if using.nil? && npc_action.nil?

    attack_name = nil
    damage_roll = nil
    sneak_attack_roll = nil
    ammo_type = nil

    if npc_action
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

    # DnD 5e advantage/disadvantage checks
    @advantage_mod = target_advantage_condition(battle, @source, target, weapon)

    # perform the dice rolls
    attack_roll = Natural20::DieRoll.roll("1d20+#{attack_mod}", disadvantage: with_disadvantage?,
                                                                advantage: with_advantage?,
                                                                description: t('dice_roll.attack'), entity: @source, battle: battle)

    # handle the lucky feat
    attack_roll = attack_roll.reroll(lucky: true) if @source.class_feature?('lucky') && attack_roll.nat_1?

    if @source.class_feature?('sneak_attack') && (weapon[:properties]&.include?('finesse') || weapon[:type] == 'ranged_attack') && (with_advantage? || battle.enemy_in_melee_range?(
      target, [@source]
    ))
      sneak_attack_roll = Natural20::DieRoll.roll(@source.sneak_attack_level, crit: attack_roll.nat_20?,
                                                                              description: t('dice_roll.sneak_attack'), entity: @source, battle: battle)
    end

    damage = Natural20::DieRoll.roll(damage_roll, crit: attack_roll.nat_20?, description: t('dice_roll.damage'),
                                                  entity: @source, battle: battle)

    # apply weapon bonus attacks
    damage = check_weapon_bonuses(battle, weapon, damage, attack_roll)

    cover_ac_adjustments = 0
    hit = if attack_roll.nat_20?
            true
          elsif attack_roll.nat_1?
            false
          else
            cover_ac_adjustments = calculate_cover_ac(battle.map, target) if battle.map
            attack_roll.result >= (target.armor_class + cover_ac_adjustments)
          end

    @result = if hit
                [{
                  source: @source,
                  target: target,
                  type: :damage,
                  thrown: thrown,
                  weapon: using,
                  battle: battle,
                  damage_roll: damage_roll,
                  attack_name: attack_name,
                  attack_roll: attack_roll,
                  sneak_attack: sneak_attack_roll,
                  target_ac: target.armor_class,
                  cover_ac: cover_ac_adjustments,
                  hit?: hit,
                  damage_type: weapon[:damage_type],
                  damage: damage,
                  ammo: ammo_type,
                  second_hand: second_hand,
                  npc_action: npc_action
                }]
              else
                [{
                  attack_name: attack_name,
                  source: @source,
                  target: target,
                  weapon: using,
                  battle: battle,
                  thrown: thrown,
                  type: :miss,
                  second_hand: second_hand,
                  damage_roll: damage_roll,
                  attack_roll: attack_roll,
                  target_ac: target.armor_class,
                  cover_ac: cover_ac_adjustments,
                  ammo: ammo_type,
                  npc_action: npc_action
                }]
              end

    self
  end

  # Computes cover armor class adjustment
  # @param map [Natural20::BattleMap]
  # @param target [Natural20::Entity]
  # @return [Integer]
  def calculate_cover_ac(map, target)
    cover_calculation(map, @source, target)
  end

  protected

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
    battle.nil? || (entity.total_bonus_actions(battle).positive? && battle.two_weapon_attack?(entity) && options[:weapon] != battle.first_hand_weapon(entity) || entity.equipped_weapons.select do |a|
      a == battle.first_hand_weapon(entity)
    end.size >= 2)
  end

  def second_hand
    true
  end

  def label
    "Bonus Action -> #{super}"
  end
end
