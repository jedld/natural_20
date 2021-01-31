RSpec.describe ShoveAction do
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
    map.move_to!(@npc, 1, 1, @battle)
  end

  specify 'knock Prone' do
    puts Natural20::MapRenderer.new(map).render
    action = ShoveAction.build(session, @fighter).next.call(@npc).next.call
    action.knock_prone = true
    srand(1000)
    @battle.action!(action)
    @battle.commit(action)
    expect(@npc.prone?).to be
  end

  context 'push' do
    specify 'against wall' do
      puts Natural20::MapRenderer.new(map).render
      action = ShoveAction.build(session, @fighter).next.call(@npc).next.call
      srand(1000)
      @battle.action!(action)
      @battle.commit(action)

      expect(map.entity_or_object_pos(@npc)).to eq([1, 1]) # shove against wall?
    end

    specify 'shove down' do
      map.move_to!(@fighter, 1, 1, @battle)
      map.move_to!(@npc, 1, 2, @battle)
      puts Natural20::MapRenderer.new(map).render
      action = ShoveAction.build(session, @fighter).next.call(@npc).next.call
      srand(1000)
      expect(map.entity_or_object_pos(@npc)).to eq([1, 2])
      @battle.action!(action)
      @battle.commit(action)

      expect(map.entity_or_object_pos(@npc)).to eq([1, 3])
    end
  end
end
