# typed: false
module Natural20
  module Entity
    include EntityStateEvaluator

    attr_accessor :entity_uid, :statuses, :color, :session, :death_saves, :death_fails

    def label
      I18n.exists?(name, :en) ? I18n.t(name) : name.humanize
    end

    def race
      @properties[:race]
    end

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

    def heal!(amt)
      return if dead?

      prev_hp = @hp
      @death_saves = 0
      @death_fails = 0
      @hp = [max_hp, @hp + amt].min

      conscious!
      Natural20::EventManager.received_event({ source: self, event: :heal, previous: prev_hp, new: @hp, value: amt })
    end

    # @option damage_params damage [Natural20::DieRoll]
    # @option damage_params sneak_attack [Natural20::DieRoll]
    # @param battle [Natural20::Battle]
    def take_damage!(damage_params, battle = nil)
      dmg = damage_params[:damage].result
      dmg += damage_params[:sneak_attack].result unless damage_params[:sneak_attack].nil?

      dmg = (dmg / 2.to_f).floor if resistant_to?(damage_params[:damage_type])
      @hp -= dmg

      if unconscious?
        @death_fails += if damage_params[:attack_roll].nat_20?
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
      elsif @hp <= 0
        npc? ? dead! : unconscious!
      end

      @hp = 0 if @hp <= 0

      on_take_damage(battle, damage_params) if battle

      Natural20::EventManager.received_event({ source: self, event: :damage, value: dmg })
    end

    def resistant_to?(damage_type)
      @resistances.include?(damage_type)
    end

    def dead!
      Natural20::EventManager.received_event({ source: self, event: :died })
      @statuses.add(:dead)
    end

    def prone!
      Natural20::EventManager.received_event({ source: self, event: :prone })
      @statuses.add(:prone)
    end

    def stand!
      Natural20::EventManager.received_event({ source: self, event: :stand })
      @statuses.delete(:prone)
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

    def melee_squares(map, target_position, adjacent_only: false)
      result = []
      step = adjacent_only ? 1 : melee_distance / map.feet_per_grid
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

          result << position
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
                            free_object_interaction: 1
                          })
      entity_state[:statuses].delete(:dodge)
      entity_state[:statuses].delete(:disengage)
      battle.dismiss_help_actions_for(self)

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
      grappled? ? 0 : battle.entity_state_for(self)[:movement]
    end

    def speed
      @properties[:speed]
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

    def passive_perception
      @properties[:passive_perception] || 10 + wis_mod
    end

    def standing_jump_distance
      (@ability_scores.fetch(:str) / 2).floor
    end

    def long_jump_distance
      @ability_scores.fetch(:str)
    end

    def token_size
      square_size = size.to_sym
      case square_size
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

    def perception_check!(battle = nil, description: nil)
      modifiers = if perception_proficient?
                    wis_mod + proficiency_bonus
                  else
                    wis_mod
                  end
      DieRoll.roll("1d20+#{modifiers}", description: description || t('dice_roll.perception'), entity: self,
                                        battle: battle)
    end

    def stealth_check!(battle = nil)
      dexterity_check!(stealth_proficient? ? proficiency_bonus : 0, battle: battle)
    end

    def acrobatics_check!(battle = nil, description: nil)
      dexterity_check!(acrobatics_proficient? ? proficiency_bonus : 0, battle: battle,
                                                                       description: description || t('dice_roll.acrobatics'))
    end

    def athletics_check!(battle = nil, description: nil)
      strength_check!(athletics_proficient? ? proficiency_bonus : 0, battle: battle,
                                                                     description: description || t('dice_roll.athletics'))
    end

    def dexterity_check!(bonus = 0, battle: nil, description: nil)
      DieRoll.roll("1d20+#{dex_mod + bonus}", description: description || t('dice_roll.dexterity'), entity: self,
                                              battle: battle)
    end

    def strength_check!(bonus = 0, battle: nil, description: nil)
      DieRoll.roll("1d20+#{str_mod + bonus}", description: description || t('dice_roll.stength_check'), entity: self,
                                              battle: battle)
    end

    def int_mod
      modifier_table(@ability_scores.fetch(:int))
    end

    def dex_mod
      modifier_table(@ability_scores.fetch(:dex))
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
        item = @session.load_weapon(k) || @session.load_equipment(k) || @session.load_object(k)
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

    # Checks if an item is equipped
    # @param item_name [String,Symbol]
    # @return [Boolean]
    def equipped?(item_name)
      equipped_items.map(&:name).include?(item_name.to_sym)
    end

    # Equips an item
    # @param item_name [String,Symbol]
    def equip(item_name)
      item = deduct_item(item_name)
      @properties[:equipped] << item_name.to_s if item
    end

    # Checks if item can be equipped
    # @param item_name [String,Symbol]
    # @return [Symbol]
    def check_equip(item_name)
      item_name = item_name.to_sym
      weapon = @session.load_weapon(item_name) || @session.load_equipment(item_name)
      return :unequippable unless weapon && weapon[:subtype] == 'weapon' || %w[shield armor].include?(weapon[:type])

      hand_slots = used_hand_slots

      armor_slots = equipped_items.select do |item|
        item.type == 'armor'
      end.size

      return :hands_full if hand_slots >= 2.0 && (weapon[:subtype] == 'weapon' || weapon[:type] == 'shield')
      return :armor_equipped if armor_slots >= 1 && weapon[:type] == 'armor'

      :ok
    end

    def used_hand_slots(weapon_only: false)
      equipped_items.select do |item|
        item.subtype == 'weapon' || (!weapon_only && item.type == 'shield')
      end.inject(0.0) do |slot, item|
        slot + (item.light ? 0.5 : 1.0)
      end
    end

    def proficient?(prof)
      @properties[:skills]&.include?(prof.to_s) ||
        @properties[:tools]&.include?(prof.to_s)
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
    # @return [Array] A List of items
    def equipped_items
      equipped_arr = @properties[:equipped] || []
      equipped_arr.map do |k|
        item = @session.load_weapon(k) || @session.load_equipment(k) || @session.load_object(k)
        raise "unknown item #{k}" unless item

        OpenStruct.new(
          name: k.to_sym,
          label: item[:label].presence || k.to_s.humanize,
          type: item[:type],
          subtype: item[:subtype],
          light: item[:properties].try(:include?, :light),
          qty: 1,
          equipped: true,
          weight: item[:weight]
        )
      end
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
      @properties[:skills].include?('perception')
    end

    def investigation_proficient?
      @properties[:skills].include?('investigation')
    end

    def insight_proficient?
      @properties[:skills].include?('insight')
    end

    def stealth_proficient?
      @properties[:skills].include?('stealth')
    end

    def acrobatics_proficient?
      proficient?('acrobatics')
    end

    def athletics_proficient?
      proficient?('athletics')
    end

    def lockpick!(battle = nil)
      proficiency_mod = dex_mod
      proficiency_mod += proficiency_bonus if proficient?(:thieves_tools)
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

    def light_properties; end

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
                    dex_mod
                  end

      modifier
    end

    def proficient_with_weapon?(weapon)
      return true if weapon[:name] == 'Unarmed Attack'

      @properties[:weapon_proficiencies]&.detect do |prof|
        weapon[:proficiency_type]&.include?(prof)
      end
    end

    protected

    # Localization helper
    # @param token [Symbol, String]
    # @param options [Hash]
    # @return [String]
    def t(token, options = {})
      I18n.t(token, options)
    end

    def setup_attributes
      @death_saves = 0
      @death_fails = 0
    end

    def on_take_damage(battle, damage_params); end

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