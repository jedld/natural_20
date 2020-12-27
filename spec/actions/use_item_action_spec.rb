RSpec.describe UseItemAction do
  let(:session) { Session.new }
  let(:entity) { PlayerCharacter.load(File.join('fixtures', 'high_elf_fighter.yml')) }

  before do
    @action = auto_build_self(entity, session, described_class,
                              select_item: 'healing_potion',
                              select_target: entity)
  end

  context 'heal thyself' do
    specify 'resolve and apply' do
      expect(entity.item_count('healing_potion')).to eq(1)
      @action.resolve(session)
      @action.apply!(nil)
      expect(entity.item_count('healing_potion')).to eq(0)
    end
  end
end
