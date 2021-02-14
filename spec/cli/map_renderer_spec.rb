RSpec.describe Natural20::MapRenderer do
  let(:session) { Natural20::Session.new }
  before do
    String.disable_colorization true
    @battle_map = Natural20::BattleMap.new(session, 'fixtures/large_map')
    @map_renderer = Natural20::MapRenderer.new(@battle_map)
    @fighter = Natural20::PlayerCharacter.load(session, File.join('fixtures', 'high_elf_fighter.yml'))
    @battle_map.place(0, 1, @fighter, 'G')
  end

  xspecify "able to render a map" do
    expect(@map_renderer.render(line_of_sight: @fighter)).to eq(
      "···········****··\n" +
      "G·······*********\n" +
      "·······**********\n" +
      "·········**g****·\n" +
      "-----------------\n" +
      "·················\n" +
      "·················\n" +
      "·················\n" +
      "-----------------\n" +
      "············*····\n" +
      "····*····*******·\n" +
      "··········******·\n" +
      "········*******··\n" +
      "········g········\n" +
      "·················\n" +
      "·················\n"
    )
  end
end