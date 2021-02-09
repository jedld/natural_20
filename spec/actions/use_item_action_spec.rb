# typed: false
RSpec.describe UseItemAction do
  let(:session) { Natural20::Session.new }
  let(:entity) { Natural20::PlayerCharacter.load(session, File.join("fixtures", "high_elf_fighter.yml")) }

  before do
    @action = auto_build_self(entity, session, described_class,
                              select_item: "healing_potion",
                              select_target: entity)
  end

  context "heal thyself" do
    specify "resolve and apply" do
      expect(entity.item_count("healing_potion")).to eq(1)
      @action.resolve(session)
      UseItemAction.apply!(nil, @action.result.first)
      expect(entity.item_count("healing_potion")).to eq(0)
    end
  end
end
