# typed: true
module Natural20
  class Session
    attr_reader :root_path, :game_properties, :game_time

    # @param root_path [String] The current adventure working folder
    # @return [Natural20::Session]
    def self.new_session(root_path = nil)
      @session = Natural20::Session.new(root_path)
      @session
    end

    # @return [Natural20::Session]
    def self.current_session
      @session
    end

    # @param session [Natural20::Session]
    def self.set_session(session)
      @session = session
    end

    def initialize(root_path = nil)
      @root_path = root_path.presence || '.'
      @session_state = {}
      @weapons = {}
      @equipment = {}
      @objects = {}
      @thing = {}
      @char_classes = {}
      @spells = {}
      @settings = {
        manual_dice_roll: false
      }
      @game_time = 0 # game time in seconds

      I18n.load_path << Dir[File.join(@root_path, 'locales') + '/*.yml']
      I18n.default_locale = :en
      if File.exist?(File.join(@root_path, 'game.yml'))
        @game_properties = YAML.load_file(File.join(@root_path, 'game.yml')).deep_symbolize_keys!
      else
        raise t(:missing_game)
      end
    end

    VALID_SETTINGS = %i[manual_dice_roll].freeze

    # @options settings manual_dice_roll [Boolean]
    def update_settings(settings = {})
      settings.each_key { |k| raise 'invalid settings' unless VALID_SETTINGS.include?(k.to_sym) }

      @settings.deep_merge!(settings.deep_symbolize_keys)
    end

    def setting(k)
      raise 'invalid settings' unless VALID_SETTINGS.include?(k.to_sym)

      @settings[k.to_sym]
    end

    def increment_game_time!(seconds = 6)
      @game_time += seconds
    end

    def load_characters
      files = Dir[File.join(@root_path, 'characters', '*.yml')]
      @characters ||= files.map do |file|
        YAML.load_file(file)
      end
      @characters.map do |char_content|
        Natural20::PlayerCharacter.new(self, char_content)
      end
    end

    # store a state
    # @param state_type [String,Symbol]
    # @param value [Hash]
    def save_state(state_type, value = {})
      @session_state[state_type.to_sym] ||= {}
      @session_state[state_type.to_sym].deep_merge!(value)
    end

    def load_state(state_type)
      @session_state[state_type.to_sym] || {}
    end

    def has_save_game?
      File.exist?(File.join(@root_path, 'savegame.yml'))
    end

    # @param battle [Natural20::BattleMap]
    def save_game(battle)
      File.write(File.join(@root_path, 'savegame.yml'), battle.to_yaml)
    end

    def save_character(name, data)
      File.write(File.join(@root_path, 'characters', "#{name}.yml"), data.to_yaml)
    end

    # @return [Natural20::Battle]
    def load_save
      YAML.load_file(File.join(@root_path, 'savegame.yml'))
    end

    def npc(npc_type, options = {})
      Natural20::Npc.new(self, npc_type, options)
    end

    def load_npcs
      files = Dir[File.join(@root_path, 'npcs', '*.yml')]
      files.map do |fname|
        npc_name = File.basename(fname, '.yml')
        Natural20::Npc.new(self, npc_name, rand_life: true)
      end
    end

    def load_races
      files = Dir[File.join(@root_path, 'races', '*.yml')]
      files.map do |fname|
        race_name = File.basename(fname, '.yml')
        [race_name, YAML.load_file(fname).deep_symbolize_keys!]
      end.to_h
    end

    def load_classes
      files = Dir[File.join(@root_path, 'char_classes', '*.yml')]
      files.map do |fname|
        class_name = File.basename(fname, '.yml')
        [class_name, YAML.load_file(fname).deep_symbolize_keys!]
      end.to_h
    end

    def load_spell(spell)
      @spells[spell.to_sym] ||= begin
        spells = YAML.load_file(File.join(@root_path, 'items', "spells.yml")).deep_symbolize_keys!
        spells[spell.to_sym].merge(id: spell)
      end
    end

    def load_class(klass)
      @char_classes[klass.to_sym] ||= begin
        YAML.load_file(File.join(@root_path, 'char_classes', "#{klass}.yml")).deep_symbolize_keys!
      end
    end

    def load_weapon(weapon)
      @weapons[weapon.to_sym] ||= begin
        weapons = YAML.load_file(File.join(@root_path, 'items', 'weapons.yml')).deep_symbolize_keys!
        weapons[weapon.to_sym]
      end
    end

    def load_weapons
      YAML.load_file(File.join(@root_path, 'items', 'weapons.yml')).deep_symbolize_keys!
    end

    def load_thing(item)
      @thing[item.to_sym] ||= begin
        load_weapon(item) || load_equipment(item) || load_object(item)
      end
    end

    def load_equipment(item)
      @equipment[item.to_sym] ||= begin
        equipment = YAML.load_file(File.join(@root_path, 'items', 'equipment.yml')).deep_symbolize_keys!
        equipment[item.to_sym]
      end
    end

    def load_object(object_name)
      @objects[object_name.to_sym] ||= begin
        objects = YAML.load_file(File.join(@root_path, 'items', 'objects.yml')).deep_symbolize_keys!
        objects[object_name.to_sym]
      end
    end

    def t(token, options = {})
      I18n.t(token, options)
    end
  end
end
