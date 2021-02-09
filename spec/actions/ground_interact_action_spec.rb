# typed: false
RSpec.describe GroundInteractAction do
  let(:session) { Natural20::Session.new }
  let(:entity) { Natural20::PlayerCharacter.load(session, File.join('fixtures', 'high_elf_fighter.yml')) }

  before do
    @battle_map = Natural20::BattleMap.new(session, 'fixtures/battle_sim_objects')
    @battle = Natural20::Battle.new(session, @battle_map)
    @battle.add(entity, :a, position: [0, 5])
    entity.reset_turn!(@battle)

    @action = GroundInteractAction.new(session, entity, :ground_interact)
  end

  specify 'dropping and picking up items' do
    inventory = entity.inventory.first

    expect do
      entity.drop_items!(@battle, [[inventory, 1]])
    end.to change { entity.item_count(inventory.name) }.from(1).to(0)

    expect(@battle_map.items_on_the_ground(entity).map(&:second).flatten.map(&:name)).to eq([:shield])

    expect do
      @action.ground_items = @battle_map.items_on_the_ground(entity).map do |ground_and_items|
        g, t = ground_and_items
        [g, t.map { |i| [i, 1] }]
      end
      @action.resolve(session, @battle_map, battle: @battle)
      @battle.commit(@action)
    end.to change { entity.item_count(inventory.name) }.from(0).to(1)
  end
end
