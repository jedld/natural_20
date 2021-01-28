RSpec.describe GrappleAction do
  let(:session) { Natural20::Session.new }
  let(:map) { Natural20::BattleMap.new(session, 'fixtures/battle_sim_objects') }

  before do
    Natural20::EventManager.standard_cli
    String.disable_colorization true
    @battle = Natural20::Battle.new(session, map)
    @fighter = Natural20::PlayerCharacter.load(session, File.join('fixtures', 'high_elf_fighter.yml'))
    @npc = session.npc(:goblin)
    @battle.add(@fighter, :a, position: :spawn_point_1, token: 'G')
    @battle.add(@npc, :b, position: :spawn_point_2, token: 'g')
    @npc.reset_turn!(@battle)
    @fighter.reset_turn!(@battle)
    Natural20::EventManager.standard_cli
    map.move_to!(@fighter, 1, 2, @battle)
    map.move_to!(@npc,1, 1, @battle)
  end

  specify 'grappling' do
    puts Natural20::MapRenderer.new(map).render
    action = GrappleAction.build(session, @fighter).next.call(@npc).next.call
    srand(1000)
    @battle.action!(action)
    @battle.commit(action)
    expect(@npc.grappled?).to be
  end

  specify 'escape grappling' do
    @npc.grappled_by!(@fighter)
    action = EscapeGrappleAction.build(session, @npc).next.call(@fighter).next.call
    srand(1000)
    @battle.action!(action)
    @battle.commit(action)
    expect(@npc.grappled?).to_not be
  end

  context "movement and grappling" do
    before do
      @npc.grappled_by!(@fighter)
    end

    it "moves grappled creature alongside" do
      puts Natural20::MapRenderer.new(map).render
      action = @battle.action(@fighter, :move, move_path: [[1, 2], [1, 3]])
      @battle.commit(action)
      puts Natural20::MapRenderer.new(map).render
      expect(map.entity_or_object_pos(@npc)).to eq([1, 2])
    end
  end
end
