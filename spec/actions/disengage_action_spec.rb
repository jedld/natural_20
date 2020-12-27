RSpec.describe DisengageAction do
  let(:session) { Session.new }
  before do
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
    cont = DisengageAction.build(session, @npc)
    dodge_action = cont.next.call()
    dodge_action.resolve(session, nil, battle: @battle)
    dodge_action.apply!(@battle)
    expect(@npc.disengage?(@battle)).to be
  end
end
