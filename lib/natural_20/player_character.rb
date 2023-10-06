# typed: false
module Natural20
  class PlayerCharacter
    include Natural20::Entity
    include Natural20::RogueClass
    include Natural20::FighterClass
    include Natural20::WizardClass
    include Natural20::HealthFlavor
    prepend Natural20::Lootable
    include Multiattack

    attr_accessor :hp, :other_counters, :resistances, :experience_points, :class_properties, :spell_slots

    ACTION_LIST = %i[spell first_aid look attack move dash hide help dodge disengage use_item interact ground_interact inventory disengage_bonus
                     dash_bonus hide_bonus grapple escape_grapple drop_grapple shove push prone stand short_rest two_weapon_attack].freeze

    # @param session [Natural20::Session]
    def initialize(session, properties)
      @session = session
      @properties = properties.deep_symbolize_keys!
      @spell_slots = {}
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

      setup_attributes
    end

    def name
      @properties[:name]
    end

    def max_hp
      if class_feature?('dwarven_toughness')
        @properties[:max_hp] + level
      else
        @properties[:max_hp]
      end
    end

    def armor_class
      current_ac = if has_effect?(:ac_override)
                     eval_effect(:ac_override, armor_class: equipped_ac)
                   else
                     equipped_ac
                   end
      if has_effect?(:ac_bonus)
        current_ac + eval_effect(:ac_bonus)
      else
        current_ac
      end
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
      effective_speed = if subrace
                          (@race_properties.dig(:subrace, subrace.to_sym,
                                                :base_speed) || @race_properties[:base_speed])
                        else
                          @race_properties[:base_speed]
                        end

      if has_effect?(:speed_override)
        effective_speed = eval_effect(:speed_override, stacked: true,
                                                       value: @properties[:speed])
      end
      effective_speed
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
      return true if @race_properties[:skills]&.include?(prof)
      return true if weapon_proficiencies.include?(prof)

      super
    end

    def proficient_with_weapon?(weapon)
      weapon = @session.load_thing weapon if weapon.is_a?(String)

      all_weapon_proficiencies = weapon_proficiencies

      return true if all_weapon_proficiencies.include?(weapon[:name].to_s.underscore)

      all_weapon_proficiencies&.detect do |prof|
        weapon[:proficiency_type]&.include?(prof)
      end
    end

    def weapon_proficiencies
      all_weapon_proficiencies = @class_properties.values.map do |p|
        p[:weapon_proficiencies]
      end.compact.flatten + @properties.fetch(:weapon_proficiencies, [])

      all_weapon_proficiencies += @race_properties.fetch(:weapon_proficiencies, [])
      if subrace
        all_weapon_proficiencies += (@race_properties.dig(:subrace, subrace.to_sym,
                                                          :weapon_proficiencies) || [])
      end

      all_weapon_proficiencies
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
      return 5 unless @properties[:equipped]

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

    def player_character_attack_actions(_battle, opportunity_attack: false)
      # check all equipped and create attack for each
      valid_weapon_types = if opportunity_attack
                             %w[melee_attack]
                           else
                             %w[ranged_attack melee_attack]
                           end

      weapon_attacks = @properties[:equipped]&.map do |item|
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

        attacks
      end&.flatten&.compact || []

      unarmed_attack = AttackAction.new(session, self, :attack)
      unarmed_attack.using = 'unarmed_attack'

      weapon_attacks + [unarmed_attack]
    end

    def available_actions(session, battle, opportunity_attack: false)
      return [] if unconscious?

      if opportunity_attack
        if AttackAction.can?(self, battle, opportunity_attack: true)
          return player_character_attack_actions(battle, opportunity_attack: true)
        else
          return []
        end
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
        when :spell
          SpellAction.new(session, self, type)
        when :two_weapon_attack
          two_weapon_attack_actions(battle)
        when :push
          ShoveAction.new(session, self, type)
        else
          Natural20::Action.new(session, self, type)
        end
      end.compact.flatten + c_class.keys.map { |c| send(:"special_actions_for_#{c}", session, battle) }.flatten
    end

    def two_weapon_attack_actions(battle)
      @properties[:equipped]&.each do |item|
        weapon_detail = session.load_weapon(item)
        next if weapon_detail.nil?
        next unless weapon_detail[:type] == 'melee_attack'

        next unless weapon_detail[:properties] && weapon_detail[:properties].include?('light') && TwoWeaponAttackAction.can?(
          self, battle, weapon: item
        )

        action = TwoWeaponAttackAction.new(session, self, :attack, weapon: item)
        action.using = item
        return action
      end
      nil
    end

    def available_interactions(_entity, _battle)
      []
    end

    def class_feature?(feature)
      return true if @properties[:class_features]&.include?(feature)
      return true if @properties[:attributes]&.include?(feature)
      return true if @race_properties[:race_features]&.include?(feature)
      return true if subrace && @race_properties.dig(:subrace, subrace.to_sym, :class_features)&.include?(feature)
      return true if subrace && @race_properties.dig(:subrace, subrace.to_sym, :race_features)&.include?(feature)

      @class_properties.values.detect { |p| p[:class_features]&.include?(feature) }
    end

    # Loads a pregen character from path
    # @param session [Natural20::Session] The session to use
    # @param path [String] path to character sheet YAML
    # @apram override [Hash] override attributes
    # @return [Natural20::PlayerCharacter] An instance of PlayerCharacter
    def self.load(session, path, override = {})
      Natural20::PlayerCharacter.new(session, YAML.load_file(File.join(session.root_path, path)).deep_symbolize_keys!.merge(override))
    end

    # returns if an npc or a player character
    # @return [Boolean]
    def npc?
      false
    end

    # Returns the number of spell slots
    # @param level [Integer]
    # @return [Integer]
    def spell_slots(level, character_class = nil)
      character_class = @spell_slots.keys.first if character_class.nil?
      @spell_slots[character_class].fetch(level, 0)
    end

    # Returns the number of spell slots
    # @param level [Integer]
    # @return [Integer]
    def max_spell_slots(level, character_class = nil)
      character_class = @spell_slots.keys.first if character_class.nil?

      return send(:"max_slots_for_#{character_class}", level) if respond_to?(:"max_slots_for_#{character_class}")

      0
    end

    # Consumes a characters spell slot
    def consume_spell_slot!(level, character_class = nil, qty = 1)
      character_class = @spell_slots.keys.first if character_class.nil?
      if @spell_slots[character_class][level]
        @spell_slots[character_class][level] = [@spell_slots[character_class][level] - qty, 0].max
      end
    end

    def pc?
      true
    end

    def prepared_spells
      @properties.fetch(:cantrips, []) + @properties.fetch(:prepared_spells, [])
    end

    # Returns the available spells for the current user
    # @param battle [Natural20::Battle]
    # @return [Hash]
    def spell_list(battle)
      prepared_spells.map do |spell|
        details = session.load_spell(spell)
        next unless details

        _qty, resource = details[:casting_time].split(':')

        disable_reason = []
        disable_reason << :no_action if resource == 'action' && battle && battle.ongoing? && total_actions(battle).zero?
        disable_reason << :reaction_only if resource == 'reaction'

        if resource == 'bonus_action' && battle.ongoing? && total_bonus_actions(battle).zero?
          disable_reason << :no_bonus_action
        elsif resource == 'hour' && battle.ongoing?
          disable_reason << :in_battle
        end
        disable_reason << :no_spell_slot if details[:level].positive? && spell_slots(details[:level]).zero?

        [spell, details.merge(disabled: disable_reason)]
      end.compact.to_h
    end

    # @param battle [Natural20::Battle]
    # @return [Array<String>]
    def available_spells(battle)
      spell_list(battle).reject do |_k, v|
        !v[:disabled].empty?
      end.keys
    end

    # @param hit_die_num [Integer] number of hit die to use
    def short_rest!(battle, prompt: false)
      super
      @class_properties.keys.each do |klass|
        send(:"short_rest_for_#{klass}", battle) if respond_to?(:"short_rest_for_#{klass}")
      end
    end

    private

    def proficiency_bonus_table
      [2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 6, 6, 6, 6]
    end

    def setup_attributes
      super
      @hp = max_hp
    end

    def equipped_ac
      @equipments ||= YAML.load_file(File.join(session.root_path, 'items', 'equipment.yml')).deep_symbolize_keys!

      equipped_meta = @equipped&.map { |e| @equipments[e.to_sym] }&.compact || []
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
