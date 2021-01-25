# typed: false
RSpec.describe AiController::Standard do
  let(:session) { Natural20::Session.new }
  let(:controller) { AiController::Standard.new }

  # setup battle scenario
  # Gomerin vs a goblin and an ogre
  before do
    String.disable_colorization true
    Natural20::EventManager.clear
    Natural20::EventManager.standard_cli
  end

  context 'standard tests' do
    before do
      @map = Natural20::BattleMap.new(session, 'fixtures/battle_sim_2')
      @battle = Natural20::Battle.new(session, @map)

      controller.register_battle_listeners(@battle)

      @fighter = Natural20::PlayerCharacter.load(session, File.join('fixtures', 'high_elf_fighter.yml'))
      @npc1 = session.npc(:goblin)
      @npc2 = session.npc(:ogre)

      @battle.add(@fighter, :a, position: :spawn_point_1, token: 'G')
      @battle.add(@npc1, :b, position: :spawn_point_2, token: 'g')
      @battle.add(@npc2, :b, position: :spawn_point_3, token: 'g')
      Natural20::EventManager.register_event_listener([:died], ->(event) { puts "#{event[:source].name} died." })
      Natural20::EventManager.register_event_listener([:unconscious], lambda { |event|
                                                                       puts "#{event[:source].name} unconscious."
                                                                     })
      Natural20::EventManager.register_event_listener([:initiative], lambda { |event|
                                                                       puts "#{event[:source].name} rolled a #{event[:roll]} = (#{event[:value]}) with dex tie break for initiative."
                                                                     })
      srand(7000)
    end

    specify 'performs standard attacks' do
      @battle.start
      @battle.while_active do |entity|
        if entity == @fighter
          target = [@npc1, @npc2].select(&:conscious?).first
          break if target.nil?

          action = @battle.action(@fighter, :move, move_path: [[2, 3], [2, 4], [2, 5]])
          @battle.commit(action)

          action = @battle.action(@fighter, :attack, target: target, using: 'vicious_rapier')
          @battle.commit(action)
        elsif [@npc1, @npc2].include?(entity)
          action = controller.move_for(entity, @battle)

          @battle.action!(action)
          @battle.commit(action)
        end
      end
      expect(@fighter.hp).to eq 36
      expect(@npc1.hp).to eq 0
      expect(@npc2.hp).to eq 0
    end
  end

  context 'movement test' do
    before do
      @map = Natural20::BattleMap.new(session, 'fixtures/battle_sim_objects')
      @battle = Natural20::Battle.new(session, @map)
      controller.register_battle_listeners(@battle)
      @fighter = Natural20::PlayerCharacter.load(session, File.join('fixtures', 'high_elf_fighter.yml'))
      @npc1 = session.npc(:goblin)
      controller.register_handlers_on(@npc1)
      @battle.add(@fighter, :a, position: :spawn_point_1, token: 'G')
      @battle.add(@npc1, :b, position: :spawn_point_3, token: 'g')
      @battle.start([@npc1, @fighter])
      srand(7000)
    end

    specify "evalute movement options" do
      puts Natural20::MapRenderer.new(@map).render
      @npc1.reset_turn!(@battle)
      state = @battle.entity_state_for(@npc1)
      state[:action] = 0 # force movement only
      action = controller.move_for(@npc1, @battle)
      expect(action.move_path).to eq([[5, 1], [4, 2], [3, 2], [2, 1]])
    end
  end

  context 'opportunity attack' do
    before do
      @map = Natural20::BattleMap.new(session, 'fixtures/battle_sim_2')
      @battle = Natural20::Battle.new(session, @map)
      controller.register_battle_listeners(@battle)
      @fighter = Natural20::PlayerCharacter.load(session, File.join('fixtures', 'high_elf_fighter.yml'))
      @npc1 = session.npc(:goblin)
      controller.register_handlers_on(@npc1)
      @battle.add(@fighter, :a, position: :spawn_point_1, token: 'G')
      @battle.add(@npc1, :b, position: :spawn_point_4, token: 'g')
      @battle.start([@npc1, @fighter])
      srand(7000)
    end

    it 'allows for opportunity attacks' do
      Natural20::EventManager.standard_cli
      expect(Natural20::MapRenderer.new(@map).render).to eq(
        "······\n" +
        "······\n" +
        "······\n" +
        "··Gg··\n" +
        "······\n" +
        "······\n"
      )
      @battle.while_active do |entity|
        if entity == @fighter
          # move away
          action = @battle.action(@fighter, :move, move_path: [[2, 3], [1, 3]])
          @battle.commit(action)
          break
        end
      end
      expect(@battle.battle_log.map(&:action_type)).to eq(%i[attack move])
    end
  end
end
