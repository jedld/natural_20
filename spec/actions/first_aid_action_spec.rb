RSpec.describe FirstAidAction do
  let(:session) { Natural20::Session.new }
  let(:map) { Natural20::BattleMap.new(session, 'fixtures/battle_sim_objects') }

  before do
    Natural20::EventManager.standard_cli
    String.disable_colorization true
    @battle = Natural20::Battle.new(session, map)
    @fighter = Natural20::PlayerCharacter.load(session, File.join('fixtures', 'high_elf_fighter.yml'))
    @rogue = Natural20::PlayerCharacter.load(session, File.join('fixtures', 'halfling_rogue.yml'))
    @battle.add(@fighter, :a, position: :spawn_point_1, token: 'G')
    @battle.add(@rogue, :b, position: :spawn_point_2, token: 'g')
    @rogue.reset_turn!(@battle)
    @fighter.reset_turn!(@battle)
    Natural20::EventManager.standard_cli
    map.move_to!(@fighter, 1, 2)
    map.move_to!(@rogue,1, 1)
    @rogue.unconscious!
  end

  specify '#can?' do
    puts Natural20::MapRenderer.new(map).render
    expect(FirstAidAction.can?(@fighter, @battle)).to be
  end

  specify 'Performing first aid' do
    puts Natural20::MapRenderer.new(map).render
    expect(@rogue.stable?).to_not be
    action = FirstAidAction.build(session, @fighter).next.call(@rogue).next.call
    srand(1000)
    @battle.action!(action)
    @battle.commit(action)
    expect(@rogue.stable?).to be
  end
end
