# typed: false
RSpec.describe DodgeAction do
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
    expect(@npc.dodge?(@battle)).to_not be
    cont = DodgeAction.build(session, @npc)
    dodge_action = cont.next.call
    dodge_action.resolve(session, nil, battle: @battle)
    @battle.commit(dodge_action)
    expect(@npc.dodge?(@battle)).to be

    cont = AttackAction.build(session, @fighter)
    begin
      param = cont.param&.map do |p|
        case (p[:type])
        when :select_target
          @npc
        when :select_weapon
          'vicious_rapier'
        else
          raise "unknown #{p.type}"
        end
      end
      cont = cont.next.call(*param)
    end while !param.nil?
    expect(cont.target).to eq(@npc)
    expect(cont.source).to eq(@fighter)
    expect(cont.using).to eq('vicious_rapier')
  end
end
