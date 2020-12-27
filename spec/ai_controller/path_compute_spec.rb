RSpec.describe AiController::PathCompute do
  let(:session) { Session.new }

  context "medium size" do
    before do
      String.disable_colorization true
      @map = BattleMap.new(session, 'fixtures/path_finding_test')
      @fighter = PlayerCharacter.load(File.join('fixtures', 'high_elf_fighter.yml'))
      @path_compute = AiController::PathCompute.new(nil, @map, @fighter)
    end

    specify 'compute' do
      expect(@map.render).to eq("········\n" +
                                "····#···\n" +
                                "···##···\n" +
                                "····#···\n" +
                                "········\n" +
                                "·######·\n" +
                                "········\n")
      expect(@path_compute.compute_path(0, 0, 6, 6)).to eq([[0, 0], [1, 1], [2, 2], [3, 3], [4, 4], [5, 4], [6, 4], [7, 5], [6, 6]])
      expect(@map.render(path: @path_compute.compute_path(0, 0, 6, 6))).to eq("X·······\n" +
        "·+··#···\n" +
        "··+##···\n" +
        "···+#···\n" +
        "····+++·\n" +
        "·######+\n" +
        "······+·\n")
    end
  end

  context "large creatures" do
    before do
      String.disable_colorization true
      @battle_map = BattleMap.new(session, 'fixtures/battle_sim_3')
      @npc = Npc.new(:ogre, name: "grok")
      @battle_map.place(0, 1, @npc)
      @path_compute = AiController::PathCompute.new(nil, @battle_map, @npc)
    end

    specify "compute" do
      expect(@battle_map.render).to eq(
        "#######\n" +
        "O┐····#\n" +
        "└┘····#\n" +
        "####··#\n" +
        "······#\n" +
        "······#\n" +
        "·······\n")
      expect(@path_compute.compute_path(0, 1, 0, 4)).to eq([[0, 1], [1, 1], [2, 1], [3, 1], [4, 2], [4, 3], [3, 4], [2, 4], [1, 4], [0, 4]])
      expect(@battle_map.render(path: @path_compute.compute_path(0, 1, 0, 4))).to eq( "#######\n" +
        "X+++··#\n" +
        "└┘··+·#\n" +
        "####+·#\n" +
        "++++··#\n" +
        "······#\n" +
        "·······\n")
        expect(@path_compute.compute_path(3, 4, 4, 5)).to eq([[3, 4], [4, 5]])
        path_back = @path_compute.compute_path(0, 4, 0, 1)
        expect(path_back).to eq([[0, 4], [1, 4], [2, 4], [3, 4], [4, 3], [4, 2], [3, 1], [2, 1], [1, 1], [0, 1]])
        
    end

    context "no path" do
      before do
        String.disable_colorization true
        @battle_map = BattleMap.new(session, 'fixtures/battle_sim_4')
        @npc = Npc.new(:ogre, name: "grok")
        @battle_map.place(0, 1, @npc)
        @path_compute = AiController::PathCompute.new(nil, @battle_map, @npc)
      end

      specify "compute" do
        expect(@battle_map.render).to eq(
          "#######\n" +
          "O┐····#\n" +
          "└┘····#\n" +
          "#######\n" +
          "······#\n" +
          "······#\n" +
          "#######\n")
        expect(@path_compute.compute_path(0, 1, 0, 4)).to be_nil
      end
    end
  end
end
