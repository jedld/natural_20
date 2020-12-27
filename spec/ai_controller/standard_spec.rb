# typed: false
RSpec.describe AiController::Standard do
  let(:session) { Natural20::Session.new }
  let(:controller) { AiController::Standard.new }

  # setup battle scenario
  # Gomerin vs a goblin and an ogre
  before do
    Natural20::EventManager.clear
    Natural20::EventManager.standard_cli
  end

  context "standard tests" do
    before do
      @map = Natural20::BattleMap.new(session, "fixtures/battle_sim_2")
      @battle = Natural20::Battle.new(session, @map)

      controller.register_battle_listeners(@battle)

      @fighter = Natural20::PlayerCharacter.load(session, File.join("fixtures", "high_elf_fighter.yml"))
      @npc1 = session.npc(:goblin)
      @npc2 = session.npc(:ogre)

      @battle.add(@fighter, :a, position: :spawn_point_1, token: "G")
      @battle.add(@npc1, :b, position: :spawn_point_2, token: "g")
      @battle.add(@npc2, :b, position: :spawn_point_3, token: "g")
      Natural20::EventManager.register_event_listener([:died], ->(event) { puts "#{event[:source].name} died." })
      Natural20::EventManager.register_event_listener([:unconsious], ->(event) { puts "#{event[:source].name} unconsious." })
      Natural20::EventManager.register_event_listener([:initiative], ->(event) { puts "#{event[:source].name} rolled a #{event[:roll]} = (#{event[:value]}) with dex tie break for initiative." })
      srand(7000)
    end

    specify "performs standard attacks" do
      @battle.start
      @battle.while_active do |entity|
        if entity == @fighter
          target = [@npc1, @npc2].select { |a| a.concious? }.first
          action = @battle.action(@fighter, :move, move_path: [[2, 3], [2, 4], [2, 5]])
          @battle.commit(action)
          action = @battle.action(@fighter, :attack, target: target, using: "vicious_rapier")
          @battle.commit(action)
        elsif entity == @npc1 || entity == @npc2
          action = controller.move_for(entity, @battle)

          @battle.action!(action)
          @battle.commit(action)
        end
      end
      expect(@fighter.hp).to eq 53
      expect(@npc1.hp).to eq 0
      expect(@npc2.hp).to eq 0
    end
  end

  specify "simulate battle" do
  end
end
