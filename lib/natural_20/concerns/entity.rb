# typed: false
module Natural20
  module Entity
    include EntityStateEvaluator

    attr_accessor :entity_uid, :statuses, :color, :session, :death_saves, :effects, :flying,
                  :death_fails, :current_hit_die, :max_hit_die, :entity_event_hooks, :concentration
    attr_reader :casted_effects

    ATTRIBUTE_TYPES = %w[strength dexterity constitution intelligence wisdom charisma].freeze
    ATTRIBUTE_TYPES_ABBV = %w[str dex con int wis cha].freeze

    def pronoun(object = false)
      return (object ? t(:"pronoun.his") : t(:"pronoun.he")) if @properties[:pronoun].blank?

      p1, p2, p3 = @properties[:pronoun].split('/')

      t(:"pronoun.#{object ? p2 : p1}")
    end

    def label
      I18n.exists?(name, :en) ? I18n.t(name) : name.humanize
    end

    def level; end

    def race
      @properties[:race]
    end

    def familiar?
      @properties[:familiar]
    end

    def token_image
      @properties[:token_image] || "token_#{(@properties[:kind] || @properties[:sub_type] || @properties[:name])&.downcase}.png"
    end

    def subrace; end

    def all_ability_scores
      %i[str dex con int wis cha].map do |att|
        @ability_scores[att]
      end
    end

    def all_ability_mods
      %i[str dex con int wis cha].map do |att|
        modifier_table(@ability_scores.fetch(att))
      end
    end

    def expertise?(prof)
      @properties[:expertise]&.include?(prof.to_s)
    end

    def damage_vulnerabilities
      @properties.fetch(:damage_vulnerabilities, [])
    end

    def vulnerable_to?(damage_type)
      damage_vulnerabilities.include?(damage_type.to_s)
    end

    def heal!(amt)
      return if dead?

      amt = eval_effect(:heal_override, heal: amt) if has_effect?(:heal_override)

      prev_hp = @hp
      @death_saves = 0
      @death_fails = 0
      @hp = [max_hp, @hp + amt].min

      if @hp.positive? && amt.positive?
        conscious! if unconscious?
        Natural20::EventManager.received_event({ source: self, event: :heal, previous: prev_hp, new: @hp, value: amt })
      end
    end

    # @param dmg [Integer]
    # @param battle [Natural20::Battle]
    # @param critical [Boolean]
    def take_damage!(dmg, battle: nil, critical: false)
      @hp -= dmg

      if unconscious?
        @statuses.delete(:stable)
        @death_fails += if critical
                          2
                        else
                          1
                        end

        complete = false
        if @death_fails >= 3
          complete = true
          dead!
          @death_saves = 0
          @death_fails = 0
        end
        Natural20::EventManager.received_event({ source: self, event: :death_fail, saves: @death_saves,
                                                 fails: @death_fails, complete: complete })
      end

      if @hp.negative? && @hp.abs >= @properties[:max_hp]
        dead!

        battle.remove(self) if battle && familiar?
      elsif @hp <= 0
        npc? ? dead! : unconscious!
        battle.remove(self) if battle && familiar?
      end

      @hp = 0 if @hp <= 0

      Natural20::EventManager.received_event({ source: self, event: :damage, value: dmg })
    end

    def resistant_to?(damage_type)
      @resistances.include?(damage_type)
    end

    def dead!
      unless dead?
        Natural20::EventManager.received_event({ source: self, event: :died })
        drop_grapple!
        @statuses.add(:dead)
        @statuses.delete(:stable)
        @statuses.delete(:unconscious)
      end
    end

    def prone!
      Natural20::EventManager.received_event({ source: self, event: :prone })
      @statuses.add(:prone)
    end

    def stand!
      Natural20::EventManager.received_event({ source: self, event: :stand })
      @statuses.delete(:prone)
    end

    def fly!
      @flying = true if @properties[:speed_fly]
    end

    def can_fly?
      @properties[:speed_fly].presence
    end

    def flying?
      !!@flying
    end

    def prone?
      @statuses.include?(:prone)
    end

    def dead?
      @statuses.include?(:dead)
    end

    def unconscious?
      !dead? && @statuses.include?(:unconscious)
    end

    def conscious?
      !dead? && !unconscious?
    end

    def stable?
      @statuses.include?(:stable)
    end

    def object?
      false
    end

    def npc?
      false
    end

    def pc?
      false
    end

    def sentient?
      npc? || pc?
    end

    def conscious!
      @statuses.delete(:unconscious)
      @statuses.delete(:stable)
    end

    def stable!
      @statuses.add(:stable)
      @death_fails = 0
      @death_saves = 0
    end

    # convenience method used to determine if a creature
    # entered or is at melee range of another
    def entered_melee?(map, entity, pos_x, pos_y)
      entity_1_sq = map.entity_squares(self)
      entity_2_sq = map.entity_squares_at_pos(entity, pos_x, pos_y)

      entity_1_sq.each do |entity_1_pos|
        entity_2_sq.each do |entity_2_pos|
          cur_x, cur_y = entity_1_pos
          pos_x, pos_y = entity_2_pos

          distance = Math.sqrt((cur_x - pos_x)**2 + (cur_y - pos_y)**2).floor * map.feet_per_grid # one square - 5 ft

          # determine melee options
          return true if distance <= melee_distance
        end
      end

      false
    end

    def melee_distance
      0
    end

    # @param map [Natural20::BattleMap]
    def push_from(map, pos_x, pos_y, distance = 5)
      x, y = map.entity_or_object_pos(self)
      effective_token_size = token_size - 1
      ofs_x, ofs_y = if pos_x.between?(x, x + effective_token_size) && !pos_y.between?(y, y + effective_token_size)
                       [0, y - pos_y > 0 ? distance : -distance]
                     elsif pos_y.between?(y, y + effective_token_size) && !pos_x.between?(x, x + effective_token_size)
                       [x - pos_x > 0 ? distance : -distance, 0]
                     elsif [pos_x, pos_y] == [x - 1, y - 1]
                       [distance, distance]
                     elsif [pos_x, pos_y] == [x + effective_token_size + 1, y - 1]
                       [-distance, distance]
                     elsif [pos_x, pos_y] == [x - 1, y + effective_token_size + 1]
                       [distance, -distance]
                     elsif [pos_x, pos_y] == [x + effective_token_size + 1, y + effective_token_size + 1]
                       [-disance, -distance]
                     else
                       raise "invalid source position #{pos_x}, #{pos_y}"
                     end
      # convert to squares
      ofs_x /= map.feet_per_grid
      ofs_y /= map.feet_per_grid

      [x + ofs_x, y + ofs_y] if map.placeable?(self, x + ofs_x, y + ofs_y)
    end

    # @param map [Natural20::BattleMap]
    # @param target_position [Array<Integer,Integer>]
    # @param adjacent_only [Boolean] If false uses melee distance otherwise uses fixed 1 square away
    def melee_squares(map, target_position: nil, adjacent_only: false, squeeze: false)
      result = []
      if adjacent_only
        cur_x, cur_y = target_position || map.entity_or_object_pos(self)
        entity_squares = map.entity_squares_at_pos(self, cur_x, cur_y, squeeze)
        entity_squares.each do |sq|
          (-1..1).each do |x_off|
            (-1..1).each do |y_off|
              next if x_off.zero? && y_off.zero?

              # adjust melee position based on token size
              adjusted_x_off = x_off
              adjusted_y_off = y_off

              position = [sq[0] + adjusted_x_off, sq[1] + adjusted_y_off]

              if entity_squares.include?(position) || result.include?(position) || position[0].negative? || position[0] >= map.size[0] || position[1].negative? || position[1] >= map.size[1]
                next
              end

              result << position
            end
          end
        end
      else
        step = melee_distance / map.feet_per_grid
        cur_x, cur_y = target_position || map.entity_or_object_pos(self)
        (-step..step).each do |x_off|
          (-step..step).each do |y_off|
            next if x_off.zero? && y_off.zero?

            # adjust melee position based on token size
            adjusted_x_off = x_off
            adjusted_y_off = y_off

            adjusted_x_off -= token_size - 1 if x_off.negative?
            adjusted_y_off -= token_size - 1 if y_off.negative?

            position = [cur_x + adjusted_x_off, cur_y + adjusted_y_off]

            if position[0].negative? || position[0] >= map.size[0] || position[1].negative? || position[1] >= map.size[1]
              next
            end

            result << position
          end
        end
      end
      result
    end

    def locate_melee_positions(map, target_position, battle = nil)
      result = []
      step = melee_distance / map.feet_per_grid
      cur_x, cur_y = target_position
      (-step..step).each do |x_off|
        (-step..step).each do |y_off|
          next if x_off.zero? && y_off.zero?

          # adjust melee position based on token size
          adjusted_x_off = x_off
          adjusted_y_off = y_off

          adjusted_x_off -= token_size - 1 if x_off < 0
          adjusted_y_off -= token_size - 1 if y_off < 0

          position = [cur_x + adjusted_x_off, cur_y + adjusted_y_off]

          if position[0].negative? || position[0] >= map.size[0] || position[1].negative? || position[1] >= map.size[1]
            next
          end
          next unless map.placeable?(self, *position, battle)

          result << position
        end
      end
      result
    end

    def languages
      @properties[:languages] || []
    end

    def darkvision?(distance)
      return false unless @properties[:darkvision]
      return false if @properties[:darkvision] < distance

      true
    end

    def unconscious!
      return if unconscious? || dead?

      drop_grapple!
      Natural20::EventManager.received_event({ source: self, event: :unconscious })
      @statuses.add(:unconscious)
    end

    def description
      @properties[:description].presence || ''
    end

    def initiative!(battle = nil)
      roll = Natural20::DieRoll.roll("1d20+#{dex_mod}", description: t('dice_roll.initiative'), entity: self,
                                                        battle: battle)
      value = roll.result.to_f + @ability_scores.fetch(:dex) / 100.to_f
      Natural20::EventManager.received_event({ source: self, event: :initiative, roll: roll, value: value })
      value
    end

    # Perform a death saving throw
    def death_saving_throw!(battle = nil)
      roll = Natural20::DieRoll.roll('1d20', description: t('dice_roll.death_saving_throw'), entity: self,
                                             battle: battle)
      if roll.nat_20?
        conscious!
        heal!(1)

        Natural20::EventManager.received_event({ source: self, event: :death_save, roll: roll, saves: @death_saves,
                                                 fails: death_fails, complete: true, stable: true, success: true })
      elsif roll.result >= 10
        @death_saves += 1
        complete = false

        if @death_saves >= 3
          complete = true
          @death_saves = 0
          @death_fails = 0
          stable!
        end
        Natural20::EventManager.received_event({ source: self, event: :death_save, roll: roll, saves: @death_saves,
                                                 fails: @death_fails, complete: complete, stable: complete })
      else
        @death_fails += roll.nat_1? ? 2 : 1
        complete = false
        if @death_fails >= 3
          complete = true
          dead!
          @death_saves = 0
          @death_fails = 0
        end

        Natural20::EventManager.received_event({ source: self, event: :death_fail, roll: roll, saves:  @death_saves,
                                                 fails: @death_fails, complete: complete })
      end
    end

    # @param battle [Natural20::Battle]
    # @return [Hash]
    def reset_turn!(battle)
      entity_state = battle.entity_state_for(self)
      entity_state.merge!({
                            action: 1,
                            bonus_action: 1,
                            reaction: 1,
                            movement: speed,
                            free_object_interaction: 1,
                            active_perception: 0,
                            active_perception_disadvantage: 0,
                            two_weapon: nil
                          })
      entity_state[:statuses].delete(:dodge)
      entity_state[:statuses].delete(:disengage)
      battle.dismiss_help_actions_for(self)
      resolve_trigger(:start_of_turn)
      cleanup_effects
      entity_state
    end

    # @param grappler [Natural20::Entity]
    def grappled_by!(grappler)
      @statuses.add(:grappled)
      @grapples ||= []
      @grapples << grappler
      grappler.grappling(self)
    end

    def escape_grapple_from!(grappler)
      @grapples ||= []
      @grapples.delete(grappler)
      @statuses.delete(:grappled) if @grapples.empty?
      grappler.ungrapple(self)
    end

    def grapples
      @grapples || []
    end

    def dodging!(battle)
      entity_state = battle.entity_state_for(self)
      entity_state[:statuses].add(:dodge)
    end

    # @param battle [Natural20::Battle]
    # @param stealth [Integer]
    def hiding!(battle, stealth)
      entity_state = battle.entity_state_for(self)
      entity_state[:statuses].add(:hiding)
      entity_state[:stealth] = stealth
    end

    def break_stealth!(battle)
      entity_state = battle.entity_state_for(self)
      return unless entity_state

      entity_state[:statuses].delete(:hiding)
      entity_state[:stealth] = 0
    end

    def disengage!(battle)
      entity_state = battle.entity_state_for(self)
      entity_state[:statuses].add(:disengage)
    end

    def disengage?(battle)
      entity_state = battle.entity_state_for(self)
      entity_state[:statuses]&.include?(:disengage)
    end

    def dodge?(battle)
      entity_state = battle.entity_state_for(self)
      return false unless entity_state

      entity_state[:statuses]&.include?(:dodge)
    end

    def has_spells?
      return false unless @properties[:prepared_spells]

      !@properties[:prepared_spells].empty?
    end

    def ranged_spell_attack!(battle, spell, advantage: false, disadvantage: false)
      DieRoll.roll("1d20+#{spell_attack_modifier}", description: t('dice_roll.ranged_spell_attack', spell: spell),
                                                    entity: self, battle: battle, advantage: advantage, disadvantage: disadvantage)
    end

    def hiding?(battle)
      entity_state = battle.entity_state_for(self)
      return false unless entity_state

      entity_state[:statuses]&.include?(:hiding)
    end

    def help?(battle, target)
      entity_state = battle.entity_state_for(target)
      return entity_state[:target_effect][self] == :help if entity_state[:target_effect]&.key?(self)

      false
    end

    # check if current entity can see target at a certain location
    def can_see?(cur_pos_x, cur_pos_y, _target_entity, pos_x, pos_y, battle)
      battle.map.line_of_sight?(cur_pos_x, cur_pos_y, pos_x, pos_y)

      # TODO, check invisiblity etc, range
      true
    end

    def help!(battle, target)
      target_state = battle.entity_state_for(target)
      target_state[:target_effect][self] = if battle.opposing?(self, target)
                                             :help
                                           else
                                             :help_ability_check
                                           end
    end

    # Checks if an entity still has an action available
    # @param battle [Natural20::Battle]
    def action?(battle = nil)
      return true if battle.nil?

      (battle.entity_state_for(self)[:action].presence || 0).positive?
    end

    def total_actions(battle)
      battle.entity_state_for(self)[:action]
    end

    def total_reactions(battle)
      battle.entity_state_for(self)[:reaction]
    end

    def free_object_interaction?(battle)
      return true unless battle

      (battle.entity_state_for(self)[:free_object_interaction].presence || 0).positive?
    end

    def total_bonus_actions(battle)
      battle.entity_state_for(self)[:bonus_action]
    end

    # @param battle [Natural::20]
    # @return [Integer]
    def available_movement(battle)
      return speed if battle.nil?

      (grappled? || unconscious?) ? 0 : battle.entity_state_for(self)[:movement]
    end

    def available_spells
      []
    end

    def speed
      c_speed = @flying ? @properties[:speed_fly] : @properties[:speed]

      return eval_effect(:speed_override, stacked: true, value: c_speed) if has_effect?(:speed_override)

      c_speed
    end

    def has_reaction?(battle)
      (battle.entity_state_for(self)[:reaction].presence || 0).positive?
    end

    def str_mod
      modifier_table(@ability_scores.fetch(:str))
    end

    def con_mod
      modifier_table(@ability_scores.fetch(:con))
    end

    def wis_mod
      modifier_table(@ability_scores.fetch(:wis))
    end

    def cha_mod
      modifier_table(@ability_scores.fetch(:cha))
    end

    def int_mod
      modifier_table(@ability_scores.fetch(:int))
    end

    def dex_mod
      modifier_table(@ability_scores.fetch(:dex))
    end

    def ability_mod(type)
      mod_type = case type.to_sym
                 when :wisdom, :wis
                   :wis
                 when :dexterity, :dex
                   :dex
                 when :constitution, :con
                   :con
                 when :intelligence, :int
                   :int
                 when :charisma, :cha
                   :cha
                 when :strength, :str
                   :str
                 end
      modifier_table(@ability_scores.fetch(mod_type))
    end

    def passive_perception
      @properties[:passive_perception] || 10 + wis_mod
    end

    def standing_jump_distance
      (@ability_scores.fetch(:str) / 2).floor
    end

    def long_jump_distance
      @ability_scores.fetch(:str)
    end

    def expertise
      @properties.fetch(:expertise, [])
    end

    def token_size
      square_size = size.to_sym
      case square_size
      when :tiny
        1
      when :small
        1
      when :medium
        1
      when :large
        2
      when :huge
        3
      else
        raise "invalid size #{square_size}"
      end
    end

    def size_identifier
      square_size = size.to_sym
      case square_size
      when :tiny
        0
      when :small
        1
      when :medium
        2
      when :large
        3
      when :huge
        4
      when :gargantuan
        5
      else
        raise "invalid size #{square_size}"
      end
    end

    ALL_SKILLS = %i[acrobatics animal_handling arcana athletics deception history insight intimidation
                    investigation medicine nature perception performance persuasion religion sleight_of_hand stealth survival]
    SKILL_AND_ABILITY_MAP = {
      dex: %i[acrobatics sleight_of_hand stealth],
      wis: %i[animal_handling insight medicine perception survival],
      int: %i[arcana history investigation nature religion],
      con: [],
      str: [:athletics],
      cha: %i[deception intimidation performance persuasion]
    }

    SKILL_AND_ABILITY_MAP.each do |ability, skills|
      skills.each do |skill|
        define_method("#{skill}_mod") do
          if npc? && @properties[:skills] && @properties[:skills][skill.to_sym]
            return @properties[:skills][skill.to_sym]
          end

          ability_mod = case ability.to_sym
                        when :dex
                          dex_mod
                        when :wis
                          wis_mod
                        when :cha
                          cha_mod
                        when :con
                          con_mod
                        when :str
                          str_mod
                        when :int
                          int_mod
                        end
          bonus = if send(:proficient?, skill)
                    expertise?(skill) ? proficiency_bonus * 2 : proficiency_bonus
                  else
                    0
                  end
          ability_mod + bonus
        end

        define_method("#{skill}_check!") do |battle = nil, opts = {}|
          modifiers = send(:"#{skill}_mod")
          DieRoll.roll_with_lucky(self, "1d20+#{modifiers}", description: opts.fetch(:description, t("dice_roll.#{skill}")),
                                                             battle: battle)
        end
      end
    end

    def dexterity_check!(bonus = 0, battle: nil, description: nil)
      disadvantage = !proficient_with_equipped_armor? ? true : false
      DieRoll.roll_with_lucky(self, "1d20+#{dex_mod + bonus}", disadvantage: disadvantage, description: description || t('dice_roll.dexterity'),
                                                               battle: battle)
    end

    def strength_check!(bonus = 0, battle: nil, description: nil)
      disadvantage = !proficient_with_equipped_armor? ? true : false
      DieRoll.roll_with_lucky(self, "1d20+#{str_mod + bonus}", disadvantage: disadvantage, description: description || t('dice_roll.stength_check'),
                                                               battle: battle)
    end

    def wisdom_check!(bonus = 0, battle: nil, description: nil)
      DieRoll.roll_with_lucky(self, "1d20+#{wis_mod + bonus}", description: description || t('dice_roll.wisdom_check'),
                                                               battle: battle)
    end

    def medicine_check!(battle = nil, description: nil)
      wisdom_check!(medicine_proficient? ? proficiency_bonus : 0, battle: battle,
                                                                  description: description || t('dice_roll.medicine'))
    end

    def attach_handler(event_name, object, callback)
      @event_handlers ||= {}
      @event_handlers[event_name.to_sym] = [object, callback]
    end

    def trigger_event(event_name, battle, session, map, event)
      @event_handlers ||= {}
      return unless @event_handlers.key?(event_name.to_sym)

      object, method_name = @event_handlers[event_name.to_sym]
      object.send(method_name.to_sym, battle, session, self, map, event)
    end

    # @param target [Natural20::Entity]
    def grappling(target)
      @grappling ||= []
      @grappling << target
    end

    def grappling?
      @grappling ||= []

      !@grappling.empty?
    end

    def grappling_targets
      @grappling ||= []
      @grappling
    end

    # @param target [Natural20::Entity]
    def ungrapple(target)
      @grappling ||= []
      @grappling.delete(target)
      target.grapples.delete(self)
      target.statuses.delete(:grappled) if target.grapples.empty?
    end

    def drop_grapple!
      @grappling ||= []
      @grappling.each do |target|
        ungrapple(target)
      end
    end

    # Removes Item from inventory
    # @param ammo_type [Symbol,String]
    # @param amount [Integer]
    # @return [OpenStruct]
    def deduct_item(ammo_type, amount = 1)
      return if @inventory[ammo_type.to_sym].nil?

      qty = @inventory[ammo_type.to_sym].qty
      @inventory[ammo_type.to_sym].qty = [qty - amount, 0].max

      @inventory[ammo_type.to_sym]
    end

    # Adds an item to your inventory
    # @param ammo_type [Symbol,String]
    # @param amount [Integer]
    # @param source_item [Object]
    def add_item(ammo_type, amount = 1, source_item = nil)
      if @inventory[ammo_type.to_sym].nil?
        @inventory[ammo_type.to_sym] =
          OpenStruct.new(qty: 0, type: source_item&.type || ammo_type.to_sym)
      end

      qty = @inventory[ammo_type.to_sym].qty
      @inventory[ammo_type.to_sym].qty = qty + amount
    end

    # Retrieves the item count of an item in the entities inventory
    # @param inventory_type [Symbol]
    # @return [Integer]
    def item_count(inventory_type)
      return 0 if @inventory[inventory_type.to_sym].nil?

      @inventory[inventory_type.to_sym][:qty]
    end

    def usable_items
      @inventory.map do |k, v|
        item_details =
          session.load_equipment(v.type)

        next unless item_details
        next unless item_details[:usable]
        next if item_details[:consumable] && v.qty.zero?

        { name: k.to_s, label: item_details[:name] || k, item: item_details, qty: v.qty,
          consumable: item_details[:consumable] }
      end.compact
    end

    # @param battle [Natural20::Batle
    # @param item_and_counts [Array<Array<OpenStruct,Integer>>]
    def drop_items!(battle, item_and_counts = [])
      ground = battle.map.ground_at(*battle.map.entity_or_object_pos(self))
      ground&.store(battle, self, ground, item_and_counts)
    end

    # Show usable objects near the entity
    # @param map [Natural20::BattleMap]
    # @param battle [Natural20::Battle]
    # @return [Array]
    def usable_objects(map, battle)
      map.objects_near(self, battle)
    end

    # Returns items in the "backpack" of the entity
    # @return [Array]
    def inventory
      @inventory.map do |k, v|
        item = @session.load_thing k
        raise "unable to load unknown item #{k}" if item.nil?
        next unless v[:qty].positive?

        OpenStruct.new(
          name: k.to_sym,
          label: v[:label].presence || k.to_s.humanize,
          qty: v[:qty],
          equipped: false,
          weight: item[:weight]
        )
      end.compact
    end

    def inventory_count
      @inventory.values.inject(0) do |total, item|
        total + item[:qty]
      end
    end

    # Unequips a weapon
    # @param item_name [String,Symbol]
    # @param transfer_inventory [Boolean] Add this item to the inventory?
    def unequip(item_name, transfer_inventory: true)
      add_item(item_name.to_sym) if @properties[:equipped].delete(item_name.to_s) && transfer_inventory
    end

    # removes all equiped. Used for tests
    def unequip_all
      @properties[:equipped].clear
    end

    # Checks if an item is equipped
    # @param item_name [String,Symbol]
    # @return [Boolean]
    def equipped?(item_name)
      equipped_items.map(&:name).include?(item_name.to_sym)
    end

    # Equips an item
    # @param item_name [String,Symbol]
    def equip(item_name, ignore_inventory: false)
      @properties[:equipped] ||= []
      if ignore_inventory
        @properties[:equipped] << item_name.to_s
        resolve_trigger(:equip)
        return
      end

      item = deduct_item(item_name)
      if item
        @properties[:equipped] << item_name.to_s
        resolve_trigger(:equip)
      end
    end

    # Checks if item can be equipped
    # @param item_name [String,Symbol]
    # @return [Symbol]
    def check_equip(item_name)
      item_name = item_name.to_sym
      weapon = @session.load_thing(item_name)
      return :unequippable unless weapon && weapon[:subtype] == 'weapon' || %w[shield armor].include?(weapon[:type])

      hand_slots = used_hand_slots + hand_slots_required(to_item(item_name, weapon))

      armor_slots = equipped_items.select do |item|
        item.type == 'armor'
      end.size

      return :hands_full if hand_slots > 2.0
      return :armor_equipped if armor_slots >= 1 && weapon[:type] == 'armor'

      :ok
    end

    def proficient_with_armor?(item)
      armor = @session.load_thing(item)
      raise "unknown item #{item}" unless armor
      raise "not armor #{item}" unless %w[armor shield].include?(armor[:type])

      return proficient?("#{armor[:subtype]}_armor") if armor[:type] == 'armor'
      return proficient?('shields') if armor[:type] == 'shield'

      false
    end

    def equipped_armor
      equipped_items.select { |t| %w[armor shield].include?(t[:type]) }
    end

    def proficient_with_equipped_armor?
      shields_and_armor = equipped_armor
      return true if shields_and_armor.empty?

      shields_and_armor.each do |item|
        return false unless proficient_with_armor?(item.name)
      end

      true
    end

    def wearing_armor?
      !!equipped_items.detect { |t| %w[armor shield].include?(t[:type]) }
    end

    def hand_slots_required(item)
      return 0.0 if item.type == 'armor'

      if item.light
        0.5
      elsif item.two_handed
        2.0
      else
        1.0
      end
    end

    def used_hand_slots(weapon_only: false)
      equipped_items.select do |item|
        item.subtype == 'weapon' || (!weapon_only && item.type == 'shield')
      end.inject(0.0) do |slot, item|
        slot + hand_slots_required(item)
      end
    end

    def equipped_weapons
      equipped_items.select do |item|
        item.subtype == 'weapon'
      end.map(&:name)
    end

    def proficient?(prof)
      @properties[:skills]&.include?(prof.to_s) ||
        @properties[:tools]&.include?(prof.to_s) ||

        @properties[:saving_throw_proficiencies]&.map { |s| "#{s}_save" }&.include?(prof.to_s)
    end

    def opened?
      false
    end

    def incapacitated?
      @statuses.include?(:unconscious) || @statuses.include?(:sleep) || @statuses.include?(:dead)
    end

    def grappled?
      @statuses.include?(:grappled)
    end

    # Returns tghe proficiency bonus of this entity
    # @return [Integer]
    def proficiency_bonus
      @properties[:proficiency_bonus].presence || 2
    end

    # returns in lbs the weight of all items in the inventory
    # @return [Float] weight in lbs
    def inventory_weight
      (inventory + equipped_items).inject(0.0) do |sum, item|
        sum + (item.weight.presence || '0').to_f * item.qty
      end
    end

    # returns equipped items
    # @return [Array<OpenStruct>] A List of items
    def equipped_items
      equipped_arr = @properties[:equipped] || []
      equipped_arr.map do |k|
        item = @session.load_thing(k)
        raise "unknown item #{k}" unless item

        to_item(k, item)
      end
    end

    def shield_equipped?
      @equipments ||= YAML.load_file(File.join(session.root_path, 'items', 'equipment.yml')).deep_symbolize_keys!

      equipped_meta = @equipped.map { |e| @equipments[e.to_sym] }.compact
      !!equipped_meta.detect do |s|
        s[:type] == 'shield'
      end
    end

    def to_item(k, item)
      OpenStruct.new(
        name: k.to_sym,
        label: item[:label].presence || k.to_s.humanize,
        type: item[:type],
        subtype: item[:subtype],
        light: item[:properties].try(:include?, 'light'),
        two_handed: item[:properties].try(:include?, 'two_handed'),
        light_properties: item[:light],
        proficiency_type: item[:proficiency_type],
        metallic: !!item[:metallic],
        qty: 1,
        equipped: true,
        weight: item[:weight]
      )
    end

    # returns the carrying capacity of an entity in lbs
    # @return [Float] carrying capacity in lbs
    def carry_capacity
      @ability_scores.fetch(:str, 1) * 15.0
    end

    def items_label
      I18n.t(:"entity.#{self.class}.item_label", default: "#{name} Items")
    end

    def perception_proficient?
      proficient?('perception')
    end

    def investigation_proficient?
      proficient?('investigation')
    end

    def insight_proficient?
      proficient?('insight')
    end

    def stealth_proficient?
      proficient?('stealth')
    end

    def acrobatics_proficient?
      proficient?('acrobatics')
    end

    def athletics_proficient?
      proficient?('athletics')
    end

    def medicine_proficient?
      proficient?('medicine')
    end

    def lockpick!(battle = nil)
      proficiency_mod = dex_mod
      bonus = if proficient?(:thieves_tools)
                expertise?(:thieves_tools) ? proficiency_bonus * 2 : proficiency_bonus
              else
                0
              end
      proficiency_mod += bonus
      Natural20::DieRoll.roll("1d20+#{proficiency_mod}", description: t('dice_roll.thieves_tools'), battle: battle,
                                                         entity: self)
    end

    def class_feature?(feature)
      @properties[:attributes]&.include?(feature)
    end

    # checks if at least one class feature matches
    # @param features [Array<String>]
    # @return [Boolean]
    def any_class_feature?(features)
      !features.select { |f| class_feature?(f) }.empty?
    end

    def light_properties
      return nil if equipped_items.blank?

      bright = [0]
      dim = [0]

      equipped_items.map do |item|
        next unless item.light_properties

        bright << item.light_properties.fetch(:bright, 0)
        dim << item.light_properties.fetch(:dim, 0)
      end

      bright = bright.max
      dim = dim.max

      return nil unless [dim, bright].sum.positive?

      { dim: dim,
        bright: bright }
    end

    def attack_roll_mod(weapon)
      modifier = attack_ability_mod(weapon)

      modifier += proficiency_bonus if proficient_with_weapon?(weapon)

      modifier
    end

    def attack_ability_mod(weapon)
      modifier = 0

      modifier += case (weapon[:type])
                  when 'melee_attack'
                    weapon[:properties]&.include?('finesse') ? [str_mod, dex_mod].max : str_mod
                  when 'ranged_attack'
                    if class_feature?('archery')
                      dex_mod + 2
                    else
                      dex_mod
                    end
                  end

      modifier
    end

    def proficient_with_weapon?(weapon)
      weapon = @session.load_thing weapon if weapon.is_a?(String)

      return true if weapon[:name] == 'Unarmed Attack'

      @properties[:weapon_proficiencies]&.detect do |prof|
        weapon[:proficiency_type]&.include?(prof) || weapon[:proficiency_type]&.include?(weapon[:name].underscore)
      end
    end

    # Returns the character hit die
    # @return [Hash<Integer,Integer>]
    def hit_die
      @current_hit_die
    end

    def squeezed!
      @statuses.add(:squeezed)
    end

    def unsqueeze
      @statuses.delete(:squeezed)
    end

    def squeezed?
      @statuses.include?(:squeezed)
    end

    # @param hit_die_num [Integer] number of hit die to use
    def short_rest!(battle, prompt: false)
      controller = battle&.controller_for(self)

      # hit die management
      if prompt && controller && controller.respond_to?(:prompt_hit_die_roll)
        loop do
          break unless @current_hit_die.values.inject(0) { |sum, d| sum + d }.positive?

          ans = battle.controller_for(self)&.try(:prompt_hit_die_roll, self, @current_hit_die.select do |_k, v|
                                                                               v.positive?
                                                                             end.keys)

          if ans == :skip
            break
          else
            use_hit_die!(ans, battle: battle)
          end
        end
      else
        while @hp < max_hp
          available_die = @current_hit_die.map do |die, num|
            next unless num.positive?

            die
          end.compact.sort

          break if available_die.empty?

          old_hp = @hp

          use_hit_die!(available_die.first, battle: battle)

          break if @hp == old_hp # break if unable to heal
        end
      end

      heal!(1) if unconscious? && stable?
    end

    def use_hit_die!(die_type, battle: nil)
      return unless @current_hit_die.key? die_type
      return unless @current_hit_die[die_type].positive?

      @current_hit_die[die_type] -= 1

      hit_die_roll = DieRoll.roll("d#{die_type}", battle: battle, entity: self, description: t('dice_roll.hit_die'))

      EventManager.received_event({ source: self, event: :hit_die, roll: hit_die_roll })

      heal!(hit_die_roll.result)
    end

    def saving_throw!(save_type, battle: nil)
      modifier = ability_mod(save_type)
      modifier += proficiency_bonus if proficient?("#{save_type}_save")
      op = modifier >= 0 ? '+' : ''
      disadvantage = %i[dex str].include?(save_type.to_sym) && !proficient_with_equipped_armor? ? true : false
      DieRoll.roll("d20#{op}#{modifier}", disadvantage: disadvantage, battle: battle, entity: self,
                                          description: t("dice_roll.#{save_type}_saving_throw"))
    end

    def active_effects
      return [] unless @effects

      @effects.values.flatten.reject do |effect|
        effect[:expiration] && effect[:expiration] <= @session.game_time
      end.uniq
    end

    def register_effect(effect_type, handler, method_name = nil, effect: nil, source: nil, duration: nil)
      @effects[effect_type.to_sym] ||= []
      effect_descriptor = {
        handler: handler,
        method: method_name.nil? ? effect_type : method_name,
        effect: effect,
        source: source
      }
      effect_descriptor[:expiration] = @session.game_time + duration.to_i if duration
      @effects[effect_type.to_sym] << effect_descriptor unless @effects[effect_type.to_sym].include?(effect_descriptor)
    end

    def register_event_hook(event_type, handler, method_name = nil, source: nil, effect: nil, duration: nil)
      @entity_event_hooks[event_type.to_sym] ||= []
      event_hook_descriptor = {
        handler: handler,
        method: method_name.nil? ? event_type : method_name,
        effect: effect,
        source: source
      }
      event_hook_descriptor[:expiration] = @session.game_time + duration.to_i if duration
      @entity_event_hooks[event_type.to_sym] << event_hook_descriptor
    end

    def spell_slots(_level)
      0
    end

    def max_spell_slots(_level)
      0
    end

    def dismiss_effect!(effect)
      @concentration = nil if @concentration == effect

      dismiss_count = effect.action.target.remove_effect(effect) if effect.action.target

      dismiss_count + remove_effect(effect)
    end

    def remove_effect(effect)
      effect.source.casted_effects.reject! { |f| f[:effect] == effect }
      dismiss_count = 0
      @effects = @effects.map do |k, value|
        delete_effects = value.select do |f|
          f[:effect] == effect
        end
        dismiss_count += delete_effects.size
        [k, value - delete_effects]
      end.to_h

      @entity_event_hooks = @entity_event_hooks.map do |k, value|
        delete_hooks = value.select do |f|
          f[:effect] == effect
        end
        dismiss_count += delete_hooks.size
        [k, value - delete_hooks]
      end.to_h

      dismiss_count
    end

    def add_casted_effect(effect)
      @casted_effects << effect
    end

    def has_spell_effect?(spell)
      active_effects = @effects.values.flatten.reject do |effect|
        effect[:expiration] && effect[:expiration] <= @session.game_time
      end

      !!active_effects.detect do |effect|
        effect[:effect].id.to_sym == spell.to_sym
      end
    end

    def undead?
      @properties[:race]&.include?('undead')
    end

    def concentration_on!(effect)
      dismiss_effect!(effect) if @concentration

      @concentration = effect
    end

    protected

    def cleanup_effects
      @effects.each do |_k, value|
        delete_effects = value.select do |f|
          f[:expiration] && f[:expiration] <= @session.game_time
        end
        delete_effects.each { |e| dismiss_effect!(e) }
      end

      @entity_event_hooks = @entity_event_hooks.map do |k, value|
        delete_hooks = value.select do |f|
          f[:expiration] && f[:expiration] <= @session.game_time
        end
        [k, value - delete_hooks]
      end.to_h

      @casted_effects.select do |f|
        f[:expiration] && f[:expiration] <= @session.game_time
      end.each { |e| dismiss_effect!(e[:effect]) }
    end

    def has_effect?(effect_type)
      return false unless @effects.key?(effect_type.to_sym)
      return false if @effects[effect_type.to_sym].empty?

      active_effects = @effects[effect_type.to_sym].reject do |effect|
        effect[:expiration] && effect[:expiration] <= @session.game_time
      end

      !active_effects.empty?
    end

    def eval_effect(effect_type, opts = {})
      return unless has_effect?(effect_type)

      active_effects = @effects[effect_type.to_sym].reject do |effect|
        effect[:expiration] && effect[:expiration] <= @session.game_time
      end

      active_effects = [active_effects.last] unless opts[:stacked]

      unless active_effects.empty?
        result = opts[:value]
        active_effects.each do |active_effect|
          result = active_effect[:handler].send(active_effect[:method], self,
                                                opts.merge(effect: active_effect[:effect], value: result))
        end
        result
      end
    end

    def resolve_trigger(event_type, opts = {})
      return unless @entity_event_hooks[event_type.to_sym]

      active_hook = @entity_event_hooks[event_type.to_sym].reject do |effect|
        effect[:expiration] && effect[:expiration] <= @session.game_time
      end.last

      active_hook[:handler].send(active_hook[:method], self, opts.merge(effect: active_hook[:effect])) if active_hook
    end

    # Localization helper
    # @param token [Symbol, String]
    # @param options [Hash]
    # @return [String]
    def t(token, options = {})
      I18n.t(token, **options)
    end

    def setup_attributes
      @death_saves = 0
      @death_fails = 0
      @entity_event_hooks = {}
      @effects = {}
      @casted_effects = []
      @concentration = nil
    end

    def on_take_damage(battle, _damage_params)
      controller = battle.controller_for(self)
      controller.attack_listener(battle, self) if controller && controller.respond_to?(:attack_listener)
    end

    def modifier_table(value)
      mod_table = [[1, 1, -5],
                   [2, 3, -4],
                   [4, 5, -3],
                   [6, 7, -2],
                   [8, 9, -1],
                   [10, 11, 0],
                   [12, 13, 1],
                   [14, 15, 2],
                   [16, 17, 3],
                   [18, 19, 4],
                   [20, 21, 5],
                   [22, 23, 6],
                   [24, 25, 7],
                   [26, 27, 8],
                   [28, 29, 9],
                   [30, 30, 10]]

      mod_table.each do |row|
        low, high, mod = row
        return mod if value.between?(low, high)
      end
    end

    def character_advancement_table
      [
        [0, 1, 2],
        [300, 2, 2],
        [900, 3, 2],
        [2700, 4, 2],
        [6500, 5, 3],
        [14_000, 6, 3],
        [23_000, 7, 3],
        [34_000, 8, 3],
        [48_000, 9, 4],
        [64_000, 10, 4],
        [85_000, 11, 4],
        [100_000, 12, 4],
        [120_000, 13, 5],
        [140_000, 14, 5],
        [165_000, 15, 5],
        [195_000, 16, 5],
        [225_000, 17, 6],
        [265_000, 18, 6],
        [305_000, 19, 6],
        [355_000, 20, 6]
      ]
    end
  end
end
