require 'natural_20/cli/commandline_ui'

RSpec.xdescribe CommandlineUI do
  let(:session) { Natural20::Session.new }
  let(:map) { Natural20::BattleMap.new(session, 'fixtures/battle_sim_objects') }
  let(:battle) { Natural20::Battle.new(session, map) }
  let(:player) { Natural20::PlayerCharacter.load(session, File.join('fixtures', 'high_elf_fighter.yml')) }

  context 'Starts a command line UI' do
    let(:command_line_ui) { CommandlineUI.new(battle, map) }

    specify do
      command_line_ui.battle_ui([player])
    end
  end
end