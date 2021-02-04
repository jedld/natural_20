# typed: false
module Natural20
  class PlayerCharacter
    include Natural20::Entity
    include Natural20::RogueClass
    include Natural20::FighterClass
    include Natural20::HealthFlavor
    prepend Natural20::Lootable
    include Multiattack

    attr_accessor :hp, :other_counters, :resistances, :experience_points, :class_properties

    ACTION_LIST = %i[first_aid look attack move dash hide help dodge disengage use_item interact ground_interact inventory disengage_bonus
                     dash_bonus hide_bonus grapple escape_grapple drop_grapple shove push prone stand short_rest].freeze

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
      @max_hit_die = {}
      @current_hit_die = {}

      @class_properties = @properties[:classes].map do |klass, level|
        send(:"#{klass}_level=", level)
        send(:"initialize_#{klass}")

        @max_hit_die[klass] = level

        character_class_properties =
          YAML.load_file(File.join(session.root_path, 'char_classes', "#{klass}.yml")).deep_symbolize_keys!
        hit_die_details = DieRoll.parse(character_class_properties[:hit_die])
        @current_hit_die[hit_die_details.die_type.to_i] = level

        [klass.to_sym, character_class_properties]
      end.to_h
    end

    def name
      @properties[:name]
    end

    def max_hp
      @properties[:max_hp]
    end

    def armor_class
      equipped_ac
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

    def race
      @properties[:race]
    end

    def subrace
      @properties[:subrace]
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

    def proficient?(prof)
      return true if @class_properties.values.detect { |c| c[:proficiencies]&.include?(prof) }

      super
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

    def player_character_attack_actions(battle, opportunity_attack: false)
      # check all equipped and create attack for each
      valid_weapon_types = if opportunity_attack
                             %w[melee_attack]
                           else
                             %w[ranged_attack melee_attack]
                           end

      weapon_attacks = @properties[:equipped].map do |item|
        weapon_detail = session.load_weapon(item)
        next if weapon_detail.nil?
        next unless valid_weapon_types.include?(weapon_detail[:type])
        next if weapon_detail[:ammo] && !item_count(weapon_detail[:ammo]).positive?

        attacks = []

        action = AttackAction.new(session, self, :attack)
        action.using = item
        attacks << action

        if !opportunity_attack && weapon_detail[:properties] && weapon_detail[:properties].include?('thrown')
          action = AttackAction.new(session, self, :attack)
          action.using = item
          action.thrown = true
          attacks << action
        end

        if !opportunity_attack && weapon_detail[:properties] && weapon_detail[:properties].include?('light') && TwoWeaponAttackAction.can?(
          self, battle, weapon: weapon_detail[:name]
        )
          action = TwoWeaponAttackAction.new(session, self, :attack_second)
          action.using = item
          attacks << action
        end
        attacks
      end.flatten.compact

      unarmed_attack = AttackAction.new(session, self, :attack)
      unarmed_attack.using = 'unarmed_attack'

      weapon_attacks + [unarmed_attack]
    end

    def available_actions(session, battle, opportunity_attack: false)
      return [] if unconscious?

      if opportunity_attack && AttackAction.can?(self, battle, opportunity_attack: true)
        return player_character_attack_actions(battle, opportunity_attack: true)
      end

      ACTION_LIST.map do |type|
        next unless "#{type.to_s.camelize}Action".constantize.can?(self, battle)

        case type
        when :look
          LookAction.new(session, self, :look)
        when :attack
          player_character_attack_actions(battle)
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
        when :short_rest
          ShortRestAction.new(session, self, type)
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
        when :first_aid
          FirstAidAction.new(session, self, type)
        when :shove
          action = ShoveAction.new(session, self, type)
          action.knock_prone = true
          action
        when :push
          ShoveAction.new(session, self, type)
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
      return true if @race_properties[:race_features]&.include?(feature)
      return true if subrace && @race_properties.dig(:subrace, subrace.to_sym, :class_features)&.include?(feature)

      @class_properties.values.detect { |p| p[:class_features]&.include?(feature) }
    end

    # Loads a pregen character from path
    # @param session [Natural20::Session] The session to use
    # @param path [String] path to character sheet YAML
    # @apram override [Hash] override attributes
    # @return [Natural20::PlayerCharacter] An instance of PlayerCharacter
    def self.load(session, path, override = {})
      Natural20::PlayerCharacter.new(session, YAML.load_file(path).deep_symbolize_keys!.merge(override))
    end

    # returns if an npc or a player character
    # @return [Boolean]
    def npc?
      false
    end

    def pc?
      true
    end

    # @param hit_die_num [Integer] number of hit die to use
    def short_rest!(battle, prompt: false)
      super

      @class_properties.keys do |klass|
        send(:"short_rest_for_#{klass}") if respond_to?(:"short_rest_for_#{klass}")
      end
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

      armor_ac = if armor.nil?
                   10 + dex_mod
                 else
                   armor[:ac] + (if armor[:mod_cap]
                                   [dex_mod,
                                    armor[:mod_cap]].min
                                 else
                                   dex_mod
                                 end) + (class_feature?('defense') ? 1 : 0)
                 end

      armor_ac + (shield.nil? ? 0 : shield[:bonus_ac])
    end
  end
end
