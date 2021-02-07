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

  context "hiding in terrain" do
    before do
      @battle_map = Natural20::BattleMap.new(session, 'fixtures/hide_test')
      @battle = Natural20::Battle.new(session, @battle_map)
      @character = Natural20::PlayerCharacter.load(session, File.join('fixtures', 'high_elf_fighter.yml'))
      @npc = session.npc(:goblin)
      @battle.add(@character, :a, position: 'spawn_point_2')
      @battle.add(@npc, :b, position: 'spawn_point_1')
    end

    it "allows to hide in a certain terrain" do
      puts Natural20::MapRenderer.new(@battle_map).render(line_of_sight: @character)
      @npc.hiding!(@battle, 20)
      expect(@npc.hiding?(@battle)).to be
      puts Natural20::MapRenderer.new(@battle_map, @battle).render(line_of_sight: @character)
    end
  end
end
