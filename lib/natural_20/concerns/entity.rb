module Entity
  attr_accessor :entity_uid, :statuses, :color

  def heal!(amt)
    prev_hp = @hp
    @hp = [max_hp, @hp + amt].min
    EventManager.received_event({ source: self, event: :heal, previous: prev_hp, new: @hp, value: amt })
  end

  def take_damage!(damage_params, battle = nil)
    dmg = damage_params[:damage].result
    dmg += damage_params[:sneak_attack].result unless damage_params[:sneak_attack].nil?

    dmg = (dmg / 2.to_f).floor if resistant_to?(damage_params[:damage_type])
    @hp -= dmg

    if @hp < 0 && @hp.abs >= @properties[:max_hp]
      dead!
    elsif @hp <= 0
      npc? ? dead! : unconcious!
    end
    @hp = 0 if @hp <= 0

    on_take_damage(battle, damage_params) if battle

    EventManager.received_event({ source: self, event: :damage, value: dmg })
  end

  def resistant_to?(damage_type)
    @resistances.include?(damage_type)
  end

  def dead!
    EventManager.received_event({ source: self, event: :died })
    @statuses.add(:dead)
  end

  def dead?
    @statuses.include?(:dead)
  end

  def unconcious?
    !dead? && @statuses.include?(:unconsious)
  end

  def concious?
    !dead? && !unconcious?
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

        distance = Math.sqrt((cur_x - pos_x)**2 + (cur_y - pos_y)**2).floor * 5 # one square - 5 ft

        # determine melee options
        return true if distance <= melee_distance
      end
    end

    false
  end

  def melee_squares(map, target_position)
    result = []
    step = melee_distance / 5
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
    step = melee_distance / 5
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

  def unconcious!
    EventManager.received_event({ source: self, event: :unconsious })
    @statuses.add(:unconsious)
  end

  def initiative!
    roll = DieRoll.roll("1d20+#{dex_mod}")
    value = roll.result.to_f + @ability_scores.fetch(:dex) / 100.to_f
    EventManager.received_event({ source: self, event: :initiative, roll: roll, value: value })
    value
  end

  # @param battle [Battle]
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

  def dodging!(battle)
    entity_state = battle.entity_state_for(self)
    entity_state[:statuses].add(:dodge)
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

  def help?(battle, target)
    entity_state = battle.entity_state_for(target)
    return entity_state[:target_effect][self] == :help if entity_state[:target_effect]&.key?(self)

    false
  end

  # check if current entity can see target at a certain location
  def can_see?(cur_pos_x, cur_pos_y, _target_entity, pos_x, pos_y, battle)
    return false unless battle.map.line_of_sight?(cur_pos_x, cur_pos_y, pos_x, pos_y)

    # TODO, check invisiblity etc, range
    true
  end

  def help!(battle, target)
    target_state = battle.entity_state_for(target)
    entity_state = battle.entity_state_for(self)
    target_state[:target_effect][self] = if target_state[:group] != entity_state[:group]
                                           :help
                                         else
                                           :help_ability_check
                                         end
  end

  # Checks if an entity still has an action available
  # @param battle [Battle]
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

  def available_movement(battle)
    battle.entity_state_for(self)[:movement]
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

  def wis_mod
    modifier_table(@ability_scores.fetch(:wis))
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

  def int_mod
    modifier_table(@ability_scores.fetch(:int))
  end

  def dex_mod
    modifier_table(@ability_scores.fetch(:dex))
  end

  def attach_handler(event_name, callback)
    @event_handlers ||= {}
    @event_handlers[event_name.to_sym] = callback
  end

  def trigger_event(event_name, battle, session, map, event)
    @event_handlers ||= {}
    @event_handlers[event_name.to_sym]&.call(battle, session, map, event)
  end

  def deduct_item(ammo_type, amount = 1)
    return if @inventory[ammo_type.to_sym].nil?

    qty = @inventory[ammo_type.to_sym][:qty]
    @inventory[ammo_type.to_sym][:qty] = qty - amount
  end

  # Retrieves the item count of an item in the entities inventory
  # @param ammo_type [Symbol]
  # @return [Integer]
  def item_count(ammo_type)
    return 0 if @inventory[ammo_type.to_sym].nil?

    @inventory[ammo_type.to_sym][:qty]
  end

  def usable_items
    @inventory.map do |k, v|
      item_details = Session.load_equipment(v.type)
      next unless item_details
      next unless item_details[:usable]
      next if item_details[:consumable] && v.qty.zero?

      { name: k.to_s, label: item_details[:name] || k, item: item_details, qty: v.qty, consumable: item_details[:consumable] }
    end.compact
  end

  # Show usable objects near the entity
  # @param map [BattleMap]
  # @param battle [Battle]
  # @return [Array]
  def usable_objects(map, battle)
    map.objects_near(self, battle)
  end

  def inventory
    @inventory.map do |k, v|
      OpenStruct.new(
        name: k.to_sym,
        label: -> { v[:label].presence || k.to_s.humanize },
        qty: v[:qty]
      )
    end
  end

  def proficient?(prof)
    @properties[:skills]&.include?(prof.to_s) ||
      @properties[:tools]&.include?(prof.to_s)
  end

  # return [Integer]
  def proficiency_bonus
    @properties[:proficiency_bonus].presence || 2
  end

  protected

  def setup_attributes
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
end
