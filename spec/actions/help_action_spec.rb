RSpec.describe HelpAction do
  let(:session) { Session.new }
  before do
    EventManager.standard_cli
    String.disable_colorization true
    @battle = Battle.new(session, nil)
    @fighter = PlayerCharacter.load(File.join("fixtures", "high_elf_fighter.yml"))
    @rogue = PlayerCharacter.load(File.join("fixtures", "halfling_rogue.yml"))
    @npc = Npc.new(:goblin, name: "Gruk")
    @battle.add(@fighter, :a)
    @battle.add(@rogue, :a)
    @battle.add(@npc, :b)
    @npc.reset_turn!(@battle)
    @fighter.reset_turn!(@battle)
  end

  it "auto build" do
    expect(@rogue.help?(@battle, @npc)).to_not be
    cont = HelpAction.build(session, @rogue)
    help_action = cont.next.call(@npc).next.call()
    help_action.resolve(session, nil, battle: @battle)
    help_action.apply!(@battle)
    expect(@rogue.help?(@battle, @npc)).to be
    expect(@battle.help_with?(@npc)).to be

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
    @battle.action!(cont)

    expect(cont.with_advantage?).to be
    @battle.commit(cont)
    expect(@battle.help_with?(@npc)).to_not be
  end
end
