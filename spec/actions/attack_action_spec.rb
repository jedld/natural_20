RSpec.describe AttackAction do
  let(:session) { Session.new }
  before do
    String.disable_colorization true
    srand(1000)
    @battle_map = BattleMap.new(session, 'fixtures/battle_sim')
    @battle = Battle.new(session, @battle_map)
    @fighter = PlayerCharacter.load(File.join('fixtures', 'high_elf_fighter.yml'))
    @npc = Npc.new(:ogre)
    @npc2 = Npc.new(:goblin)
    @battle.add(@fighter, :a, position: :spawn_point_1, token: 'G')
    @battle.add(@npc, :b, position: :spawn_point_2, token: 'g')

    @fighter.reset_turn!(@battle)
    @npc.reset_turn!(@battle)
  end

  it 'auto build' do
    cont = AttackAction.build(session, @fighter)
    loop do
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
      break if param.nil?
    end
    expect(cont.target).to eq(@npc)
    expect(cont.source).to eq(@fighter)
    expect(cont.using).to eq('vicious_rapier')
  end

  specify 'unarmed attack' do
    EventManager.standard_cli
    action = AttackAction.build(session, @fighter).next.call(@npc).next.call('unarmed_attack').next.call
    @battle.action!(action)
    @battle.commit(action)
    expect(@npc.hp).to eq(55)
  end

  specify 'range disadvantage' do
    @battle.add(@npc2, :b, position: [3, 3], token: 'O')
    @npc2.reset_turn!(@battle)
    EventManager.standard_cli
    action = AttackAction.build(session, @fighter).next.call(@npc).next.call('longbow').next.call
    @battle.action!(action)
    @battle.commit(action)
    expect(@npc.hp).to eq(51)
  end
end
