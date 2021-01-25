# typed: false
RSpec.describe Natural20::Battle do
  let(:session) { Natural20::Session.new }
  context 'Simple Natural20::Battle' do
    before do
      @map = Natural20::BattleMap.new(session, 'fixtures/battle_sim')
      @battle = Natural20::Battle.new(session, @map)
      @fighter = Natural20::PlayerCharacter.load(session, File.join('fixtures', 'high_elf_fighter.yml'))
      @npc = session.npc(:goblin, name: 'a')
      @npc2 = session.npc(:goblin, name: 'b')
      @npc3 = session.npc(:ogre, name: 'c')
      @battle.add(@fighter, :a, position: :spawn_point_1, token: 'G')
      @battle.add(@npc, :b, position: :spawn_point_4, token: 'g')
      @battle.add(@npc2, :b, position: :spawn_point_3, token: 'O')
      @fighter.reset_turn!(@battle)
      @npc.reset_turn!(@battle)
      @npc2.reset_turn!(@battle)

      Natural20::EventManager.register_event_listener([:died], ->(event) { puts "#{event[:source].name} died." })
      Natural20::EventManager.register_event_listener([:unconscious], lambda { |event|
                                                                       puts "#{event[:source].name} unconscious."
                                                                     })
      Natural20::EventManager.register_event_listener([:initiative], lambda { |event|
                                                                       puts "#{event[:source].name} rolled a #{event[:roll]} = (#{event[:value]}) with dex tie break for initiative."
                                                                     })
      srand(7000)
    end

    specify 'attack' do
      @battle.start
      srand(7000)
      action = @battle.action(@fighter, :attack, target: @npc, using: 'vicious_rapier')
      expect(action.result.first).to be_a_hash_like({
                                    ammo: nil,
                                    battle: @battle,
                                    attack_name: 'Vicious Rapier',
                                    damage_roll: '1d8+5',
                                    source: @fighter,
                                    type: :miss,
                                    target_ac: 15,
                                    cover_ac: 0,
                                    thrown: nil,
                                    attack_roll: Natural20::DieRoll.new([2], 8, 20),
                                    target: @npc,
                                    weapon: 'vicious_rapier',
                                    npc_action: nil
                                  })
      action = @battle.action(@fighter, :attack, target: @npc, using: 'vicious_rapier')
      expect(action.result).to be_a_hash_like([{
                                    ammo: nil,
                                    attack_name: 'Vicious Rapier',
                                    damage_roll: '1d8+5',
                                    type: :damage,
                                    source: @fighter,
                                    battle: @battle,
                                    attack_roll: Natural20::DieRoll.new([10], 8, 20),
                                    hit?: true,
                                    damage: Natural20::DieRoll.new([2], 5, 8),
                                    damage_type: 'piercing',
                                    target_ac: 15,
                                    cover_ac: 0,
                                    target: @npc,
                                    weapon: 'vicious_rapier',
                                    thrown: nil,
                                    sneak_attack: nil,
                                    npc_action: nil
                                  }])

      expect(@fighter.item_count('arrows')).to eq(20)
      @battle.commit(action)
      expect(@fighter.item_count('arrows')).to eq(20)

      expect(@npc.hp).to eq(0)
      expect(@npc.dead?).to be
      action = @battle.action(@npc2, :attack, target: @fighter, npc_action: @npc2.npc_actions[1])
      @battle.commit(action)

      @battle.add(@npc3, :c, position: [0, 0])

      expect(@battle.combat_order.map(&:name)).to eq(%w[a b Gomerin])
    end
  end

  context 'battle loop' do
    before do
      @battle_map = Natural20::BattleMap.new(session, 'fixtures/battle_sim_objects')
      @battle = Natural20::Battle.new(session, @battle_map)
      @map_renderer = Natural20::MapRenderer.new(@battle_map)
      @fighter = Natural20::PlayerCharacter.load(session, File.join('fixtures', 'high_elf_fighter.yml'))
      @npc2 = session.npc(:goblin, name: 'b')
      @battle.add(@fighter, :a)
      @battle.add(@npc2, :b)
    end

    specify 'death saving throws fail' do
      Natural20::EventManager.standard_cli
      srand(1000)
      @battle.start
      @fighter.take_damage!(damage: Natural20::DieRoll.new([20], 80))
      expect(@fighter.unconscious?).to be
      expect(@battle.ongoing?).to be
      @battle.while_active(3) do |entity|
      end
      expect(@battle.ongoing?).to_not be
      expect(@fighter.dead?).to be
    end

    specify 'death saving throws success' do
      Natural20::EventManager.standard_cli
      srand(2000)
      @battle.start
      @fighter.take_damage!(damage: Natural20::DieRoll.new([20], 80))
      expect(@fighter.unconscious?).to be
      @battle.while_active(3) do |entity|
      end
      expect(@fighter.stable?).to be
    end

    specify 'death saving critical success' do
      Natural20::EventManager.standard_cli

      srand(1004)
      @battle.start
      @fighter.take_damage!(damage: Natural20::DieRoll.new([20], 80))
      expect(@fighter.unconscious?).to be
      @battle.while_active(3) do |entity|
      end

      expect(@fighter.conscious?).to be
    end
  end

  context '#valid_targets_for' do
    before do
      @battle_map = Natural20::BattleMap.new(session, 'fixtures/battle_sim_objects')
      @battle = Natural20::Battle.new(session, @battle_map)
      @map_renderer = Natural20::MapRenderer.new(@battle_map)
      @fighter = Natural20::PlayerCharacter.load(session, File.join('fixtures', 'high_elf_fighter.yml'))
      @npc = session.npc(:goblin, name: 'a')
      @battle_map.place(0, 5, @fighter, 'G')
      @battle.add(@fighter, :a)
      @door = @battle_map.object_at(1, 4)
    end

    it 'shows all valid targets for attack action' do
      action = AttackAction.new(session, @fighter, :attack)
      action.using = 'vicious_rapier'
      puts @map_renderer.render
      expect(@battle.valid_targets_for(@fighter, action)).to eq([])
      @battle.add(@npc, :b, position: [1, 5])
      puts @map_renderer.render
      expect(@battle.valid_targets_for(@fighter, action)).to eq([@npc])
      expect(@battle.valid_targets_for(@fighter, action, include_objects: true)).to include @npc, @door
    end
  end

  context '#has_controller_for' do
    before do
      @battle_map = Natural20::BattleMap.new(session, 'fixtures/battle_sim_objects')
      @battle = Natural20::Battle.new(session, @battle_map)
      @fighter = Natural20::PlayerCharacter.load(session, File.join('fixtures', 'high_elf_fighter.yml'))
      @npc = session.npc(:goblin, name: 'a')
      @battle.add(@npc, :b, position: [1, 5])
      @battle.add(@fighter, :a, position: [0, 5], controller: :manual)
    end

    specify 'default controllers' do
      expect(@battle.has_controller_for?(@npc)).to be
      expect(@battle.has_controller_for?(@fighter)).to_not be
    end
  end
end
