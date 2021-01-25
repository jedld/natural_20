# typed: false
RSpec.describe HideAction do
  let(:session) { Natural20::Session.new }
  before do
    Natural20::EventManager.standard_cli
    String.disable_colorization true
    @battle = Natural20::Battle.new(session, nil)
    @fighter = Natural20::PlayerCharacter.load(session, File.join('fixtures', 'high_elf_fighter.yml'))
    @npc = session.npc(:goblin)
    @battle.add(@fighter, :a)
    @battle.add(@npc, :b)
    @npc.reset_turn!(@battle)
    @fighter.reset_turn!(@battle)
  end

  it 'auto build' do
    expect(@npc.hiding?(@battle)).to_not be
    cont = HideAction.build(session, @npc)
    hide_action = cont.next.call
    hide_action.resolve(session, nil, battle: @battle)
    hide_action.apply!(@battle)
    expect(@npc.hiding?(@battle)).to be
  end
end
