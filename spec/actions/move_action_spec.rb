RSpec.describe MoveAction do
  let(:session) { Session.new }
  let(:map) { BattleMap.new(session, "fixtures/battle_sim") }
  before do
    srand(1000)
    @battle = Battle.new(session, map)
    @fighter = PlayerCharacter.load(File.join("fixtures", "high_elf_fighter.yml"))
    @npc = Npc.new(:goblin)
    @battle.add(@fighter, :a, position: :spawn_point_1, token: "G")
    @battle.add(@npc, :b, position: :spawn_point_2, token: "g")
    @fighter.reset_turn!(@battle)
    @npc.reset_turn!(@battle)
    cont = MoveAction.build(session, @fighter)
    begin
      param = cont.param&.map { |p|
        case (p[:type])
        when :movement
          [[2,3], [2,2], [1,2]]
        else
          raise "unknown #{p.type}"
        end
      }
      cont = cont.next.call(*param)
    end while !param.nil?
    @action = cont
  end

  it "auto build" do
    @battle.action!(@action)
    @battle.commit(@action)
    expect(map.position_of(@fighter)).to eq([1,2])
  end

  specify "#opportunity_attack_list" do
    @action.move_path = [[2,5], [3,5]]
    expect(@action.opportunity_attack_list(@action.move_path, @battle, map)).to eq [{ source: @npc, path: 1 }]
  end

  context "opportunity attack large creature" do
    let(:map) { BattleMap.new(session, "fixtures/battle_sim_2") }

    specify "opportunity attacks on large creatures" do
      @ogre = Npc.new(:ogre)
      @battle.add(@ogre, :b, position: [1,1], token: "g")
      @ogre.reset_turn!(@battle)
      expect(@action.opportunity_attack_list([[1,0],[2,0],[3,0]], @battle, map).size).to eq(0)
    end
  end

  specify "opportunity attach triggers" do
    EventManager.standard_cli

    @npc.attach_handler(:opportunity_attack, -> (battle, session, map, event) {
      action = @npc.available_actions(session, battle).select { |s|
        s.action_type == :attack
      }.select { |s| s.npc_action[:type] == 'melee_attack' }.first

      action.target = event[:target]
      action.as_reaction = true
      action
    })

    @action.move_path = [[2,5], [3,5]]
    expect(@fighter.hp).to eq(67)
    @battle.action!(@action)
    @battle.commit(@action)
    expect(@fighter.hp).to eq(60)
  end
end
