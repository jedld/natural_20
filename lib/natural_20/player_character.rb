class PlayerCharacter
  include Entity
  include RogueClass
  include FighterClass
  include Multiattack

  attr_accessor :hp, :other_counters, :resistances

  def initialize(properties)
    @properties = properties.deep_symbolize_keys!
    @ability_scores = @properties[:ability]
    @equipped = @properties[:equipped]
    @race_properties = YAML.load_file(File.join(File.dirname(__FILE__), '..', 'races', "#{@properties[:race]}.yml")).deep_symbolize_keys!
    @inventory = {}
    @color = @properties[:color]
    @properties[:inventory]&.each do |inventory|
      @inventory[inventory[:type].to_sym] ||= OpenStruct.new({ type: inventory[:type], qty: 0 })
      @inventory[inventory[:type].to_sym].qty += inventory[:qty]
    end
    @statuses = Set.new
    @resistances = []
    entity_uid = SecureRandom.uuid
    setup_attributes
    @class_properties = @properties[:classes].map do |klass, level|
      send(:"#{klass}_level=", level)
      send(:"initialize_#{klass}")
      [klass.to_sym, YAML.load_file(File.join(File.dirname(__FILE__), '..', 'char_classes', "#{klass}.yml")).deep_symbolize_keys!]
    end.to_h
  end

  def name
    @properties[:name]
  end

  def max_hp
    @properties[:max_hp]
  end

  def armor_class
    equipped_ac + dex_mod
  end

  def level
    @properties[:level]
  end

  def size
    @properties[:size] || @race_properties[:size]
  end

  def token
    @properties[:token]
  end

  def speed
    @race_properties[:base_speed]
  end

  def c_class
    @properties[:classes]
  end

  def passive_perception
    10 + wis_mod + wisdom_proficiency
  end

  def passive_investigation
    10 + int_mod + investigation_proficiency
  end

  def passive_insight
    10 + wis_mod + insight_proficiency
  end

  def wisdom_proficiency
    perception_proficient? ? proficiency_bonus : 0
  end

  def investigation_proficiency
    investigation_proficient? ? proficiency_bonus : 0
  end

  def insight_proficiency
    insight_proficient? ? proficiency_bonus : 0
  end

  def proficiency_bonus
    proficiency_bonus_table[level - 1]
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

  def to_h
    {
      name: name,
      classes: c_class,
      hp: hp,
      ability: {
        str: @ability_scores.fetch(:str),
        dex: @ability_scores.fetch(:dex),
        con: @ability_scores.fetch(:con),
        int: @ability_scores.fetch(:int),
        wis: @ability_scores.fetch(:wis),
        cha: @ability_scores.fetch(:cha)
      },
      passive: {
        perception: passive_perception,
        investigation: passive_investigation,
        insight: passive_insight
      }
    }
  end

  def melee_distance
    @properties[:equipped].map do |item|
      weapon_detail = Session.load_weapon(item)
      next if weapon_detail.nil?
      next unless weapon_detail[:type] == 'melee_attack'

      weapon_detail[:range]
    end.compact.max
  end

  def available_actions(session, battle = nil)
    %i[attack move dash dash_bonus dodge help disengage disengage_bonus use_item interact inventory].map do |type|
      next unless "#{type.to_s.camelize}Action".constantize.can?(self, battle)

      case type
      when :attack
        # check all equipped and create attack for each
        weapon_attacks = @properties[:equipped].map do |item|
          weapon_detail = Session.load_weapon(item)
          next if weapon_detail.nil?
          next unless %w[ranged_attack melee_attack].include?(weapon_detail[:type])
          next if weapon_detail[:ammo] && !item_count(weapon_detail[:ammo]).positive?

          action = AttackAction.new(session, self, :attack)
          action.using = item
          action
        end.compact

        unarmed_attack = AttackAction.new(session, self, :attack)
        unarmed_attack.using = 'unarmed_attack'

        weapon_attacks + [unarmed_attack]
      when :dodge
        DodgeAction.new(session, self, :dodge)
      when :help
        action = HelpAction.new(session, self, :help)
        action
      when :disengage_bonus
        action = DisengageAction.new(session, self, :disengage_bonus)
        action.as_bonus_action = true
        action
      when :disengage
        action = DisengageAction.new(session, self, :disengage)
        action
      when :move
        MoveAction.new(session, self, type)
      when :dash_bonus
        action = DashBonusAction.new(session, self, :dash_bonus)
        action.as_dash = true
        action.as_bonus_action = true
        action
      when :dash
        action = DashAction.new(session, self, type)
        action.as_dash = true
        action
      when :use_item
        UseItemAction.new(session, self, type)
      when :interact
        InteractAction.new(session, self, type)
      when :inventory
        InventoryAction.new(session, self, type)
      else
        Action.new(session, self, type)
      end
    end.compact.flatten + c_class.keys.map { |c| send(:"special_actions_for_#{c}", session, battle) }.flatten
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

  def class_feature?(feature)
    return true if @properties[:class_features]&.include?(feature)

    @class_properties.values.detect { |p| p[:class_features]&.include?(feature) }
  end

  def self.load(path)
    fighter_prop = YAML.load_file(path).deep_symbolize_keys!
    @fighter = PlayerCharacter.new(fighter_prop)
  end

  def npc?
    false
  end

  def describe_health
    ''
  end

  private

  def proficiency_bonus_table
    [2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 6, 6, 6, 6]
  end

  def setup_attributes
    @hp = @properties[:max_hp]
  end

  def equipped_ac
    @equipments ||= YAML.load_file(File.join(File.dirname(__FILE__), '..', 'items', 'equipment.yml')).deep_symbolize_keys!

    equipped_meta = @equipped.map { |e| @equipments[e.to_sym] }.compact
    armor = equipped_meta.detect do |equipment|
      equipment[:type] == 'armor'
    end

    shield = equipped_meta.detect { |e| e[:type] == 'shield' }

    (armor.nil? ? 10 : armor[:ac]) + (shield.nil? ? 0 : shield[:bonus_ac])
  end
end
