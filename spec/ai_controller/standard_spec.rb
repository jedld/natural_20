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
        false
      end
      expect(@fighter.hp).to eq 50
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
      @fighter2 = Natural20::PlayerCharacter.load(session, File.join('fixtures', 'high_elf_fighter.yml'))
      @npc1 = session.npc(:goblin)
      @npc2 = session.npc(:wolf)
      @npc3 = session.npc(:wolf)
      controller.register_handlers_on(@npc1)
      @battle.add(@fighter, :a, position: :spawn_point_1, token: 'G')
      @battle.add(@fighter2, :a, position: [1, 2], token: 'X')
      @battle.add(@npc1, :b, position: :spawn_point_3, token: 'g')
      @battle.add(@npc2, :b, position: [1, 1])
      @battle.add(@npc3, :b, position: [6, 1])
      @battle.start([@npc1, @fighter])
      srand(7000)
    end

    specify 'evalute movement options' do
      puts Natural20::MapRenderer.new(@map).render
      @npc1.reset_turn!(@battle)
      state = @battle.entity_state_for(@npc1)
      state[:action] = 0 # force movement only
      action = nil
      begin
        action = controller.move_for(@npc1, @battle)
        @battle.action!(action)
        @battle.commit(action)
      end until action.action_type == :move
      expect(action.move_path).to eq([[5, 1], [4, 2]])
    end

    context '#candidate_squares' do
      specify 'Return all valid destination squares' do
        puts Natural20::MapRenderer.new(@map).render
        expect(controller.candidate_squares(@map, @battle, @npc1)).to eq({ [0, 2] => 9,
                                                                           [2, 1] => 6,
                                                                           [3, 1] => 4,
                                                                           [3, 2] => 4,
                                                                           [3, 3] => 4,
                                                                           [4, 1] => 2,
                                                                           [4, 2] => 2,
                                                                           [4, 3] => 4,
                                                                           [5, 1] => 0,
                                                                           [5, 2] => 2,
                                                                           [5, 3] => 3,
                                                                           [6, 2] => 1,
                                                                           [6, 3] => 2 })
      end
    end

    context '#evaluate_squares' do
      context 'goblin' do
        it 'gives a weight to a destination square' do
          puts Natural20::MapRenderer.new(@map).render
          expect(controller.evaluate_square(@map, @battle, @npc1, [@fighter])).to eq(
            { [0, 2] => [0.2, 0.0, -0.05, -0.005, 0.0],
              [2, 1] => [0.0, 0.1, 0.0, -0.003, 0.0],
              [3, 1] => [0.0, 0.1, 0.0, -0.002, 0.0],
              [3, 2] => [0.0, 0.1, 2.0, -0.002, 0.0],
              [3, 3] => [0.0, 0.1, 2.0, -0.002, 0.0],
              [4, 1] => [0.0, 0.1, 0.0, -0.001, 0.0],
              [4, 2] => [0.0, 0.1, 2.0, -0.001, 0.0],
              [4, 3] => [0.0, 0.1, 2.0, -0.002, 0.0],
              [5, 1] => [0.0, 0.1, 0.0, 0.0, 0.0],
              [5, 2] => [0.0, 0.1, 0.0, -0.001, 0.0],
              [5, 3] => [0.0, 0.1, 2.0, -0.002, 0.0],
              [6, 2] => [0.0, 0.1, 0.0, -0.001, 0.0],
              [6, 3] => [0.0, 0.1, 2.0, -0.002, 0.0] }
          )
        end
      end
      context 'wolf' do
        it 'gives a weight to a destination square' do
          puts Natural20::MapRenderer.new(@map).render(line_of_sight: @npc3)
          expect(controller.evaluate_square(@map, @battle, @npc3, [@fighter])).to eq(
            { [0, 2] => [0.3, 0.0, -0.05, -0.006, 0.0],
              [2, 1] => [0.0, 0.1, 0.0, -0.004, 0.0],
              [3, 1] => [0.0, 0.1, 0.0, -0.003, 0.0],
              [3, 2] => [0.0, 0.1, 2.0, -0.003, 0.0],
              [3, 3] => [0.0, 0.1, 2.0, -0.003, 0.0],
              [4, 1] => [0.0, 0.1, 0.0, -0.002, 0.0],
              [4, 2] => [0.0, 0.1, 2.0, -0.002, 0.0],
              [4, 3] => [0.0, 0.1, 2.0, -0.002, 0.0],
              [5, 2] => [0.0, 0.1, 0.0, -0.001, 0.0],
              [5, 3] => [0.0, 0.1, 2.0, -0.002, 0.0],
              [6, 1] => [0.0, 0.1, 0.0, 0.0, 0.0],
              [6, 2] => [0.0, 0.1, 0.0, -0.001, 0.0],
              [6, 3] => [0.0, 0.1, 2.0, -0.002, 0.0]}
          )
        end
      end

      context 'cover evaluation' do
        before do
          @map = Natural20::BattleMap.new(session, 'fixtures/hide_test')
          @battle = Natural20::Battle.new(session, @map)
          @battle.add(@fighter, :a, position: :spawn_point_1, token: 'G')
          @battle.add(@npc1, :b, position: :spawn_point_2, token: 'g')
        end

        xit 'gives correct weights' do
          puts Natural20::MapRenderer.new(@map).render(line_of_sight: @npc1)
          expect(controller.evaluate_square(@map, @battle, @npc1, [@fighter])).to eq([])
        end
      end
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
        "g·····\n" +
        "R·····\n" +
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
        false
      end
      expect(@battle.battle_log.map(&:action_type)).to eq(%i[attack move])
    end
  end
end
