class AttackAction < Action
  attr_accessor :target, :using, :npc_action, :as_reaction
  attr_reader :advantage_mod

  def self.can?(entity, battle, options = {})
    battle.nil? || entity.total_actions(battle).positive? || entity.multiattack?(battle, options[:npc_action])
  end

  def to_s
    @action_type.to_s.humanize
  end

  def label
    if @npc_action
      "#{@action_type.to_s.humanize} with #{npc_action[:name]}"
    else
      weapon = Session.load_weapon(@opts[:using] || @using)
      attack_mod = @source.attack_roll_mod(weapon)

      "#{@action_type.to_s.humanize} with #{weapon[:name]} -> Hit: +#{attack_mod} Dmg: #{damage_modifier(weapon)}"
    end
  end

  def build_map
    OpenStruct.new({
                     action: self,
                     param: [
                       {
                         type: :select_target,
                         num: 1
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

  def apply!(battle)
    @result.each do |item|
      case (item[:type])
      when :damage
        EventManager.received_event({ source: item[:source], attack_roll: item[:attack_roll], target: item[:target], event: :attacked,
                                      attack_name: item[:attack_name],
                                      damage_type: item[:damage_type],
                                      as_reaction: as_reaction,
                                      damage_roll: item[:damage],
                                      sneak_attack: item[:sneak_attack],
                                      value: item[:damage].result + (item[:sneak_attack]&.result.presence || 0) })
        item[:target].take_damage!(item, battle)
      when :miss
        EventManager.received_event({ attack_roll: item[:attack_roll],
                                      attack_name: item[:attack_name],
                                      as_reaction: as_reaction,
                                      source: item[:source], target: item[:target], event: :miss })
      end

      # handle ammo

      item[:source].deduct_item(item[:ammo], 1) if item[:ammo]

      if as_reaction
        battle.entity_state_for(item[:source])[:reaction] -= 1
      else
        battle.entity_state_for(item[:source])[:action] -= 1
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

  def damage_modifier(weapon)
    damage_mod = @source.attack_ability_mod(weapon)

    damage_mod += 2 if @source.class_feature?('dueling')

    "#{weapon[:damage]}+#{damage_mod}"
  end

  def with_advantage?
    @advantage_mod > 0
  end

  def with_disadvantage?
    @advantage_mod.negative?
  end

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
      weapon = Session.load_weapon(using.to_sym)
      attack_name = weapon[:name]
      ammo_type = weapon[:ammo]
      attack_mod = @source.attack_roll_mod(weapon)
      damage_roll = damage_modifier(weapon)
    end

    # DnD 5e advantage/disadvantage checks
    @advantage_mod = target_advantage_condition(battle, @source, target, weapon)

    # perform the dice rolls
    attack_roll = DieRoll.roll("1d20+#{attack_mod}", disadvantage: with_disadvantage?, advantage: with_advantage?)

    if @source.class_feature?('sneak_attack') && (weapon[:properties]&.include?('finesse') || weapon[:type] == 'ranged_attack')
      if with_advantage? || battle.enemy_in_melee_range?(target, [@source])
        sneak_attack_roll = DieRoll.roll(@source.sneak_attack_level, crit: attack_roll.nat_20?)
      end
    end

    damage = DieRoll.roll(damage_roll, crit: attack_roll.nat_20?)

    # apply weapon bonus attacks
    damage = check_weapon_bonuses(weapon, damage, attack_roll)

    hit = if attack_roll.nat_20?
            true
          elsif attack_roll.nat_1?
            false
          else
            attack_roll.result >= target.armor_class
          end

    @result = if hit
                [{
                  source: @source,
                  target: target,
                  type: :damage,
                  battle: battle,
                  attack_name: attack_name,
                  attack_roll: attack_roll,
                  sneak_attack: sneak_attack_roll,
                  target_ac: target.armor_class,
                  hit?: hit,
                  damage_type: weapon[:damage_type],
                  damage: damage,
                  ammo: ammo_type,
                  npc_action: npc_action
                }]
              else
                [{
                  attack_name: attack_name,
                  source: @source,
                  target: target,
                  battle: battle,
                  type: :miss,
                  attack_roll: attack_roll,
                  ammo: ammo_type,
                  npc_action: npc_action
                }]
              end

    self
  end

  protected

  def check_weapon_bonuses(weapon, damage_roll, attack_roll)
    if weapon.dig(:bonus, :additional, :restriction) == 'nat20_attack' && attack_roll.nat_20?
      damage_roll += DieRoll.roll(weapon.dig(:bonus, :additional, :die))
    end

    damage_roll
  end

  # Check all the factors that affect advantage/disadvantage in attack rolls
  def target_advantage_condition(battle, source, target, weapon)
    advantage = []
    advantage << -1 if target.dodge?(battle)
    advantage << 1 if battle.help_with?(target)

    if weapon[:type] == 'ranged_attack' && battle.map
      advantage << -1 if battle.enemy_in_melee_range?(source)
    end

    return 0 if advantage.empty?
    return 0 if advantage.uniq.size > 1

    advantage.first
  end
end
