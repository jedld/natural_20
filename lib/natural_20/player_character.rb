# typed: false
module Natural20
  class PlayerCharacter
    include Natural20::Entity
    include Natural20::RogueClass
    include Natural20::FighterClass
    prepend Natural20::Lootable
    include Multiattack

    attr_accessor :hp, :other_counters, :resistances, :experience_points

    ACTION_LIST = %i[look attack move dash hide help dodge disengage use_item interact ground_interact inventory disengage_bonus
                     dash_bonus hide_bonus grapple escape_grapple drop_grapple prone stand].freeze

    # @param session [Natural20::Session]
    def initialize(session, properties)
      @session = session
      @properties = properties.deep_symbolize_keys!

      @ability_scores = @properties[:ability]
      @equipped = @properties[:equipped]
      @race_properties = YAML.load_file(File.join(session.root_path, 'races',
                                                  "#{@properties[:race]}.yml")).deep_symbolize_keys!
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
        [klass.to_sym,
         YAML.load_file(File.join(session.root_path, 'char_classes', "#{klass}.yml")).deep_symbolize_keys!]
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

    def languages
      class_languages = []
      @class_properties.values.each do |prop|
        class_languages += prop[:languages] || []
      end

      racial_languages = @race_properties[:languages] || []

      (super + class_languages + racial_languages).sort
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
      (@properties[:equipped].map do |item|
        weapon_detail = session.load_weapon(item)
        next if weapon_detail.nil?
        next unless weapon_detail[:type] == 'melee_attack'

        weapon_detail[:range]
      end.compact + [5]).max
    end

    def darkvision?(distance)
      return true if super

      !!(@race_properties[:darkvision] && @race_properties[:darkvision] >= distance)
    end

    def available_actions(session, battle = nil)
      return [] if unconscious?

      ACTION_LIST.map do |type|
        next unless "#{type.to_s.camelize}Action".constantize.can?(self, battle)

        case type
        when :look
          LookAction.new(session, self, :look)
        when :attack
          # check all equipped and create attack for each
          weapon_attacks = @properties[:equipped].map do |item|
            weapon_detail = session.load_weapon(item)
            next if weapon_detail.nil?
            next unless %w[ranged_attack melee_attack].include?(weapon_detail[:type])
            next if weapon_detail[:ammo] && !item_count(weapon_detail[:ammo]).positive?

            attacks = []

            action = AttackAction.new(session, self, :attack)
            action.using = item
            attacks << action

            if weapon_detail[:properties] && weapon_detail[:properties].include?('thrown')
              action = AttackAction.new(session, self, :attack)
              action.using = item
              action.thrown = true
              attacks << action
            end
            attacks
          end.compact

          unarmed_attack = AttackAction.new(session, self, :attack)
          unarmed_attack.using = 'unarmed_attack'

          weapon_attacks + [unarmed_attack]
        when :dodge
          DodgeAction.new(session, self, :dodge)
        when :help
          action = HelpAction.new(session, self, :help)
          action
        when :hide
          HideAction.new(session, self, :hide)
        when :hide_bonus
          action = HideBonusAction.new(session, self, :hide_bonus)
          action.as_bonus_action = true
          action
        when :disengage_bonus
          action = DisengageAction.new(session, self, :disengage_bonus)
          action.as_bonus_action = true
          action
        when :disengage
          DisengageAction.new(session, self, :disengage)
        when :drop_grapple
          DropGrappleAction.new(session, self, :drop_grapple)
        when :grapple
          GrappleAction.new(session, self, :grapple)
        when :escape_grapple
          EscapeGrappleAction.new(session, self, :escape_grapple)
        when :move
          MoveAction.new(session, self, type)
        when :prone
          ProneAction.new(session, self, type)
        when :stand
          StandAction.new(session, self, type)
        when :dash_bonus
          action = DashBonusAction.new(session, self, :dash_bonus)
          action.as_bonus_action = true
          action
        when :dash
          action = DashAction.new(session, self, type)
          action
        when :use_item
          UseItemAction.new(session, self, type)
        when :interact
          InteractAction.new(session, self, type)
        when :ground_interact
          GroundInteractAction.new(session, self, type)
        when :inventory
          InventoryAction.new(session, self, type)
        else
          Natural20::Action.new(session, self, type)
        end
      end.compact.flatten + c_class.keys.map { |c| send(:"special_actions_for_#{c}", session, battle) }.flatten
    end

    def available_interactions(_entity, _battle)
      []
    end

    def class_feature?(feature)
      return true if @properties[:class_features]&.include?(feature)
      return true if @properties[:attributes]&.include?(feature)

      @class_properties.values.detect { |p| p[:class_features]&.include?(feature) }
    end

    # Loads a pregen character from path
    # @param session [Natural20::Session] The session to use
    # @param path [String] path to character sheet YAML
    # @return [Natural20::PlayerCharacter] An instance of PlayerCharacter
    def self.load(session, path)
      Natural20::PlayerCharacter.new(session, YAML.load_file(path).deep_symbolize_keys!)
    end

    # returns if an npc or a player character
    # @return [Boolean]
    def npc?
      false
    end

    def pc?
      true
    end

    def describe_health
      ''
    end

    private

    def proficiency_bonus_table
      [2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 6, 6, 6, 6]
    end

    def setup_attributes
      super
      @hp = @properties[:max_hp]
    end

    def equipped_ac
      @equipments ||= YAML.load_file(File.join(session.root_path, 'items', 'equipment.yml')).deep_symbolize_keys!

      equipped_meta = @equipped.map { |e| @equipments[e.to_sym] }.compact
      armor = equipped_meta.detect do |equipment|
        equipment[:type] == 'armor'
      end

      shield = equipped_meta.detect { |e| e[:type] == 'shield' }

      (armor.nil? ? 10 : armor[:ac]) + (shield.nil? ? 0 : shield[:bonus_ac])
    end
  end
end
