# typed: false
RSpec.describe AiController::PathCompute do
  let(:session) { Natural20::Session.new }

  context 'medium size' do
    before do
      String.disable_colorization true
      @map = Natural20::BattleMap.new(session, 'fixtures/path_finding_test')
      @map_renderer = Natural20::MapRenderer.new(@map)
      @fighter = Natural20::PlayerCharacter.load(session, File.join('fixtures', 'high_elf_fighter.yml'))
      @path_compute = AiController::PathCompute.new(nil, @map, @fighter)
    end

    specify 'compute' do
      expect(@map_renderer.render).to eq("········\n" +
                                "····#···\n" +
                                "···##···\n" +
                                "····#···\n" +
                                "········\n" +
                                "·######·\n" +
                                "········\n")
      expect(@path_compute.compute_path(0, 0, 6,
                                        6)).to eq([[0, 0], [1, 1], [2, 2], [3, 3], [4, 4], [5, 4], [6, 4], [7, 5],
                                                   [6, 6]])
      expect(@map_renderer.render(path: @path_compute.compute_path(0, 0, 6, 6), path_char: '+')).to eq("········\n" +
        "·+··#···\n" +
        "··+##···\n" +
        "···+#···\n" +
        "····+++·\n" +
        "·######+\n" +
        "······+·\n")
    end

    context 'difficult terrain' do
      before do
        @map = Natural20::BattleMap.new(session, 'fixtures/path_finding_test_2')
        @map_renderer = Natural20::MapRenderer.new(@map)
        @fighter = Natural20::PlayerCharacter.load(session, File.join('fixtures', 'high_elf_fighter.yml'))
        @path_compute = AiController::PathCompute.new(nil, @map, @fighter)
      end

      specify 'compute' do
        expect(@path_compute.compute_path(3, 2, 3, 5)).to eq([[3, 2], [2, 3], [1, 4], [2, 5], [3, 5]])
        expect(@map_renderer.render(path: @path_compute.compute_path(3, 2, 3, 5), path_char: '+')).to eq(
          "········\n" +
          "········\n" +
          "········\n" +
          "··+^^···\n" +
          "·+^^^···\n" +
          "··++····\n" +
          "········\n"
        )
      end
    end
  end

  context 'large creatures' do
    before do
      String.disable_colorization true
      @battle_map = Natural20::BattleMap.new(session, 'fixtures/battle_sim_3')
      @map_renderer = Natural20::MapRenderer.new(@battle_map)
      @npc = session.npc(:ogre, name: 'grok')
      @battle_map.place(0, 1, @npc)
      @path_compute = AiController::PathCompute.new(nil, @battle_map, @npc)
    end

    specify 'compute' do
      expect(@map_renderer.render).to eq(
        "#######\n" +
        "O┐····#\n" +
        "└┘····#\n" +
        "####··#\n" +
        "······#\n" +
        "······#\n" +
        "·······\n"
      )
      expect(@npc.melee_squares(@battle_map, adjacent_only: true).sort).to eq([[0, 0], [0, 3], [1, 0], [1, 3], [2, 0], [2, 1], [2, 2], [2, 3]])
      expect(@path_compute.compute_path(0, 1, 0,
                                        4)).to eq([[0, 1], [1, 1], [2, 1], [3, 2], [4, 3], [3, 4], [2, 4], [1, 4], [0, 4]])
      expect(@map_renderer.render(path: @path_compute.compute_path(0, 1, 0, 4), path_char: '+')).to eq("#######\n" +
        "O++···#\n" +
        "└┘·+··#\n" +
        "####+·#\n" +
        "++++··#\n" +
        "······#\n" +
        "·······\n")
      expect(@path_compute.compute_path(3, 4, 4, 5)).to eq([[3, 4], [4, 5]])
      path_back = @path_compute.compute_path(0, 4, 0, 1)
      expect(path_back).to eq([[0, 4], [1, 4], [2, 4], [3, 4], [4, 3], [4, 2], [3, 1], [2, 1], [1, 1], [0, 1]])
    end

    context 'difficult terrain' do
      before do
        @map = Natural20::BattleMap.new(session, 'fixtures/path_finding_test_2')
        @map_renderer = Natural20::MapRenderer.new(@map)
        @npc = session.npc(:ogre, name: 'grok')
        @map.place(3, 1, @npc)
        @path_compute = AiController::PathCompute.new(nil, @map, @npc)
      end

      specify 'compute' do
        expect(@path_compute.compute_path(3, 1, 3, 5)).to eq([[3, 1], [4, 2], [5, 3], [5, 4], [4, 5], [3, 5]])
        expect(@map_renderer.render(path: @path_compute.compute_path(3, 1, 3, 5), path_char: '+')).to eq(
          "········\n" +
          "···O┐···\n" +
          "···└+···\n" +
          "··^^^+··\n" +
          "··^^^+··\n" +
          "···++···\n" +
          "········\n"
        )
      end
    end

    context 'tight spaces' do
      before do
        @map = Natural20::BattleMap.new(session, 'fixtures/path_finding_test_3')
        @map_renderer = Natural20::MapRenderer.new(@map)
        @npc = session.npc(:ogre, name: 'grok')
        @map.place(0, 1, @npc)
        @path_compute = AiController::PathCompute.new(nil, @map, @npc)
      end
      specify 'can navigate tight spaces' do
        expect(@map_renderer.render).to eq(
          "#######\n" +
          "O┐····#\n" +
          "└┘··#·#\n" +
          "#####·#\n" +
          "····#·#\n" +
          "······#\n" +
          "·······\n"
        )
        expect(@path_compute.compute_path(0, 1, 0,
                                          4)).to eq( [[0, 1], [1, 1], [2, 1], [3, 2], [4, 1], [5, 2], [5, 3], [5, 4], [4, 5], [3, 5], [2, 4], [1, 4], [0, 4]])
        expect(@map_renderer.render(path: @path_compute.compute_path(0, 1, 0, 4), path_char: '+')).to eq("#######\n" +
          "O++·+·#\n" +
          "└┘·+#+#\n" +
          "#####+#\n" +
          "+++·#+#\n" +
          "···++·#\n" +
          "·······\n")
        expect(@path_compute.compute_path(3, 4, 4, 5)).to eq([[3, 4], [4, 5]])
        path_back = @path_compute.compute_path(0, 4, 0, 1)
        expect(path_back).to eq( [[0, 4], [1, 4], [2, 4], [3, 5], [4, 5], [5, 4], [5, 3], [5, 2], [4, 1], [3, 1], [2, 1], [1, 1], [0, 1]])
      end
    end

    context 'no path' do
      before do
        String.disable_colorization true
        @battle_map = Natural20::BattleMap.new(session, 'fixtures/battle_sim_4')
        @map_renderer = Natural20::MapRenderer.new(@battle_map)
        @npc = session.npc(:ogre, name: 'grok')
        @battle_map.place(0, 1, @npc)
        @path_compute = AiController::PathCompute.new(nil, @battle_map, @npc)
      end

      specify 'compute' do
        expect(@map_renderer.render).to eq(
          "#######\n" +
          "O┐····#\n" +
          "└┘····#\n" +
          "#######\n" +
          "······#\n" +
          "······#\n" +
          "#######\n"
        )
        expect(@path_compute.compute_path(0, 1, 0, 4)).to be_nil
      end
    end
  end
end
