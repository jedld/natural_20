RSpec.describe DodgeAction do
  let(:session) { Session.new }
  before do
    EventManager.standard_cli
    String.disable_colorization true
    @battle = Battle.new(session, nil)
    @fighter = PlayerCharacter.load(File.join("fixtures", "high_elf_fighter.yml"))
    @npc = Npc.new(:goblin)
    @battle.add(@fighter, :a)
    @battle.add(@npc, :b)
    @npc.reset_turn!(@battle)
    @fighter.reset_turn!(@battle)
  end

  it "auto build" do
    expect(@npc.dodge?(@battle)).to_not be
    cont = DodgeAction.build(session, @npc)
    dodge_action = cont.next.call()
    dodge_action.resolve(session, nil, battle: @battle)
    dodge_action.apply!(@battle)
    expect(@npc.dodge?(@battle)).to be

    cont = AttackAction.build(session, @fighter)
    begin
      param = cont.param&.map { |p|
        case (p[:type])
        when :select_target
          @npc
        when :select_weapon
          "vicious_rapier"
        else
          raise "unknown #{p.type}"
        end
      }
      cont = cont.next.call(*param)
    end while !param.nil?
    expect(cont.target).to eq(@npc)
    expect(cont.source).to eq(@fighter)
    expect(cont.using).to eq("vicious_rapier")
  end
end
