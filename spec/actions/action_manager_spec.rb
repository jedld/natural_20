RSpec.describe Natural20::ActionManager do
  let(:session) { Natural20::Session.new }

  before do
    srand(1000)
    @battle_map = Natural20::BattleMap.new(session, 'fixtures/battle_sim')
    @battle = Natural20::Battle.new(session, @battle_map)
    @character = Natural20::PlayerCharacter.load(session, File.join('fixtures', 'high_elf_fighter.yml'))
    @npc = session.npc(:ogre)
    @npc2 = session.npc(:goblin)
  end

  specify "#rollback" do
    expect(@npc.hp).to eq(59)
    transactions = []
    txn = Natural20::Transaction.new(@npc, :take_damage!, [10, {battle: @battle, critical: true }])
    txn.commit()
    expect(@npc.hp). to eq(49)
    txn.rollback()
    expect(@npc.hp). to eq(59)
  end

  specify "entity is dead" do
    expect(@npc.hp).to eq(59)
    transactions = []
    txn = Natural20::Transaction.new(@npc, :take_damage!, [60, {battle: @battle, critical: true }])
    txn.commit()
    expect(@npc.hp). to eq(0)
    expect(@npc.dead?).to be
    txn.rollback()
    
    # should not be dead
    expect(@npc.dead?).to_not be
    expect(@npc.hp). to eq(59)
  end
 
end