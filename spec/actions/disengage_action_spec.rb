# typed: false
RSpec.describe DisengageAction do
  let(:session) { Natural20::Session.new }
  before do
    @battle = Natural20::Battle.new(session, nil)
    @fighter = Natural20::PlayerCharacter.load(session, File.join("fixtures", "high_elf_fighter.yml"))
    @npc = session.npc(:goblin)
    @battle.add(@fighter, :a)
    @battle.add(@npc, :b)
    @npc.reset_turn!(@battle)
    @fighter.reset_turn!(@battle)
  end

  it "auto build" do
    expect(@npc.dodge?(@battle)).to_not be
    cont = DisengageAction.build(session, @npc)
    disengage_action = cont.next.call()
    disengage_action.resolve(session, nil, battle: @battle)
    DisengageAction.apply!(@battle, disengage_action.result.first)
    expect(@npc.disengage?(@battle)).to be
  end
end
