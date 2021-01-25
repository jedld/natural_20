# typed: false
require "random_name_generator"

module Natural20
  class Npc
    include Natural20::Entity
    include Natural20::Notable
    prepend Natural20::Lootable
    include HealthFlavor
    include Multiattack

    attr_accessor :hp, :resistances, :npc_actions, :battle_defaults

    # @param session [Session]
    # @param type [String,Symbol]
    # @option opt rand_life [Boolean] Determines if will use die for npc HP instead of fixed value
    def initialize(session, type, opt = {})
      @properties = YAML.load_file(File.join("npcs", "#{type}.yml")).deep_symbolize_keys!
      @properties.merge!(opt[:overrides].presence || {})
      @ability_scores = @properties[:ability]
      @color = @properties[:color]
      @session = session

      @inventory = @properties[:default_inventory].map do |inventory|
        [inventory[:type].to_sym, OpenStruct.new({ qty: inventory[:qty] })]
      end.to_h

      @properties[:inventory]&.each do |inventory|
        @inventory[inventory[:type].to_sym] = OpenStruct.new({ qty: inventory[:qty] })
      end

      @npc_actions = @properties[:actions]
      @battle_defaults = @properties[:battle_defaults]
      @opt = opt
      @resistances = []
      @statuses = Set.new

      @properties[:statuses]&.each do |stat|
        @statuses.add(stat.to_sym)
      end

      name = case type
        when "goblin"
          RandomNameGenerator.new(RandomNameGenerator::GOBLIN).compose(1)
        when "ogre"
          %w[Guzar Irth Grukurg Zoduk].sample(1).first
        else
          type.to_s.humanize
        end
      @name = opt.fetch(:name, name)
      @entity_uid = SecureRandom.uuid
      setup_attributes
    end

    attr_reader :name

    def kind
      @properties[:kind]
    end

    def size
      @properties[:size]
    end

    def token
      @properties[:token]
    end

    attr_reader :name

    attr_reader :max_hp

    def npc?
      true
    end

    def armor_class
      @properties[:default_ac]
    end

    def speed
      @properties[:speed]
    end

    def available_actions(session, battle = nil)
      return %i[end] if unconscious?

      %i[attack hide dodge look stand move dash grapple escape_grapple].map do |type|
        next unless "#{type.to_s.camelize}Action".constantize.can?(self, battle)

        case type
        when :attack
          # check all equipped and create attack for each
          actions = []

          actions += npc_actions.map do |npc_action|
            next if npc_action[:ammo] && item_count(npc_action[:ammo]) <= 0
            next if npc_action[:if] && !eval_if(npc_action[:if])
            next unless AttackAction.can?(self, battle, npc_action: npc_action)

            action = AttackAction.new(session, self, :attack)

            action.npc_action = npc_action
            action
          end.compact

          actions
        when :dodge
          DodgeAction.new(session, self, :dodge)
        when :hide
          HideAction.new(session, self, :hide)
        when :disengage
          action = DisengageAction.new(session, self, :disengage)
          action
        when :move
          MoveAction.new(session, self, type)
        when :stand
          StandAction.new(session, self, type)
        when :dash
          action = DashAction.new(session, self, type)
          action
        when :help
          action = HelpAction.new(session, self, :help)
          action
        else
          Natural20::Action.new(session, self, type)
        end
      end.compact.flatten
    end

    def melee_distance
      @properties[:actions].select { |a| a[:type] == "melee_attack" }.map do |action|
        action[:range]
      end&.max
    end

    def class_feature?(feature)
      @properties[:attributes]&.include?(feature)
    end

    def available_interactions(entity, battle)
      []
    end

    private

    def setup_attributes
      super

      @max_hp = @opt[:rand_life] ? Natural20::DieRoll.roll(@properties[:hp_die]).result : @properties[:max_hp]
      @hp = [@properties.fetch(:override_hp, @max_hp), @max_hp].min
    end
  end
end
