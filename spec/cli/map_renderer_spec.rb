RSpec.describe Natural20::MapRenderer do
  let(:session) { Natural20::Session.new }
  before do
    String.disable_colorization true
    @battle_map = Natural20::BattleMap.new(session, 'fixtures/large_map')
    @map_renderer = Natural20::MapRenderer.new(@battle_map)
    @fighter = Natural20::PlayerCharacter.load(session, File.join('fixtures', 'high_elf_fighter.yml'))
    @rogue = Natural20::PlayerCharacter.load(session, File.join('fixtures', 'halfling_rogue.yml'))
    @mage = Natural20::PlayerCharacter.load(session, File.join('fixtures', 'high_elf_mage.yml'))
    @battle_map.place(0, 1, @fighter, 'G')
  end

  specify 'able to render a map' do
    result = nil
    @map_renderer.render(line_of_sight: @fighter)
    benchmark = Benchmark.measure do
      result = @map_renderer.render(line_of_sight: @fighter)
    end
    puts benchmark
    expect(result).to eq(
      "···········****····*····**g···\n" +
      "G·······*********·····****····\n" +
      "·······**********····****·····\n" +
      "·········**g****······**······\n" +
      "------------------------------\n" +
      "······························\n" +
      "······························\n" +
      "······························\n" +
      "------------------------------\n" +
      "············*·················\n" +
      "····*····*******··*··******···\n" +
      "··········******······****····\n" +
      "········*******·····********··\n" +
      "········g················g····\n" +
      "······························\n" +
      "······························\n"
    )
  end
end
