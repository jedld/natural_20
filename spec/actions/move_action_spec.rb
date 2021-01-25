# typed: false
RSpec.describe MoveAction do
  let(:session) { Natural20::Session.new }

  context 'battle related' do
    let(:map) { Natural20::BattleMap.new(session, 'fixtures/battle_sim') }
    before do
      srand(1000)
      @battle = Natural20::Battle.new(session, map)
      @fighter = Natural20::PlayerCharacter.load(session, File.join('fixtures', 'high_elf_fighter.yml'))
      @npc = session.npc(:goblin)
      @battle.add(@fighter, :a, position: :spawn_point_1, token: 'G')
      @battle.add(@npc, :b, position: :spawn_point_2, token: 'g')
      @fighter.reset_turn!(@battle)
      @npc.reset_turn!(@battle)
      cont = MoveAction.build(session, @fighter)
      begin
        param = cont.param&.map do |p|
          case (p[:type])
          when :movement
            [[[2, 3], [2, 2], [1, 2]], []]
          else
            raise "unknown #{p.type}"
          end
        end
        cont = cont.next.call(*param)
      end while !param.nil?
      @action = cont
    end

    it 'auto build' do
      @battle.action!(@action)
      @battle.commit(@action)
      expect(map.position_of(@fighter)).to eq([1, 2])
    end

    specify '#opportunity_attack_list' do
      @action.move_path = [[2, 5], [3, 5]]
      expect(@action.opportunity_attack_list(@action.source, @action.move_path, @battle, map)).to eq [{ source: @npc, path: 1 }]
    end

    context 'opportunity attack large creature' do
      let(:map) { Natural20::BattleMap.new(session, 'fixtures/battle_sim_2') }

      specify 'opportunity attacks on large creatures' do
        @ogre = session.npc(:ogre)
        @battle.add(@ogre, :b, position: [1, 1], token: 'g')
        @ogre.reset_turn!(@battle)
        expect(@action.opportunity_attack_list(@action.source, [[1, 0], [2, 0], [3, 0]], @battle, map).size).to eq(0)
      end
    end

    def opportunity_attack_handler(battle, session, _entity, _map, event)
      action = @npc.available_actions(session, battle).select do |s|
        s.action_type == :attack
      end.select { |s| s.npc_action[:type] == 'melee_attack' }.first

      action.target = event[:target]
      action.as_reaction = true
      action
    end

    specify 'opportunity attach triggers' do
      srand(1000)
      Natural20::EventManager.standard_cli

      @npc.attach_handler(:opportunity_attack, self, :opportunity_attack_handler)

      @action.move_path = [[2, 5], [3, 5]]
      expect(@fighter.hp).to eq(67)
      @battle.action!(@action)
      @battle.commit(@action)
      expect(@fighter.hp).to eq(60)
    end
  end

  context 'traps' do
    let(:map) { Natural20::BattleMap.new(session, 'fixtures/traps') }

    before do
      srand(1000)
      @battle = Natural20::Battle.new(session, map)
      @fighter = Natural20::PlayerCharacter.load(session, File.join('fixtures', 'high_elf_fighter.yml'))
      @npc = session.npc(:goblin)
      @battle.add(@fighter, :a, position: :spawn_point_1, token: 'G')
      @fighter.reset_turn!(@battle)
    end

    specify 'handles traps' do
      action = @battle.action(@fighter, :move, move_path: [[0, 3], [1, 3], [2, 3], [3, 3], [4, 3]])
      expect do
        @battle.commit(action)
      end.to change { @fighter.hp }.from(67).to(63)

      expect(map.position_of(@fighter)).to eq([1, 3])
    end
  end

  context 'jumps' do
    include Natural20::MovementHelper
    let(:map) { Natural20::BattleMap.new(session, 'fixtures/battle_sim_objects') }

    before do
      Natural20::EventManager.standard_cli
      @battle = Natural20::Battle.new(session, map)
      @fighter = Natural20::PlayerCharacter.load(session, File.join('fixtures', 'high_elf_fighter.yml'))
      @battle.add(@fighter, :a, position: [0, 6], token: 'G')
      @fighter.reset_turn!(@battle)
    end

    it 'computes jumping distances' do
      puts Natural20::MapRenderer.new(map).render
      movement = compute_actual_moves(@fighter, [[0, 6], [1, 6], [2, 6]], map, @battle, 6)
      expect(movement.movement).to eq([[0, 6], [1, 6]])
      # movement = compute_actual_moves(@fighter, [[0, 6], [1, 6], [2, 6], [3, 6]], map, @battle, 6)
      # expect(movement.movement).to eq([[0, 6], [1, 6], [2, 6], [3, 6]])
      # movement = compute_actual_moves(@fighter, [[0, 6], [1, 6], [2, 6], [3, 6], [4, 6], [5, 6]], map, @battle, 6)
      # expect(movement.movement).to eq([[0, 6], [1, 6], [2, 6], [3, 6], [4, 6]])
      # movement = compute_actual_moves(@fighter, [[1, 6], [2, 6], [3, 6], [4, 6], [5, 6], [6, 6], [7, 6]],
      #                                 map, @battle, 6)
      # expect(movement.impediment).to eq(:movement_budget)
      # expect(movement.movement).to eq([[1, 6], [2, 6], [3, 6], [4, 6]])
      # expect(movement.acrobatics_check_locations).to eq([[3, 6]])
      # expect(movement.jump_locations).to eq([[2, 6], [5, 6], [6, 6]])
      # expect(movement.jump_start_locations).to eq([[2, 6], [5, 6]])
      # expect(movement.land_locations).to eq([[3, 6]])
    end

    it 'manual jumps' do
      puts Natural20::MapRenderer.new(map).render
      movement = compute_actual_moves(@fighter, [[0, 6], [1, 6], [2, 6], [3, 6], [4, 6]],
                                      map, @battle, 6, manual_jump: [2, 3])
      expect(movement.impediment).to be_nil
      expect(movement.movement).to eq([[0, 6], [1, 6], [2, 6], [3, 6], [4, 6]])
      expect(movement.budget).to eq(2)
    end

    specify 'handle acrobatics during jumps' do
      map.move_to!(@fighter, 1, 6)
      puts Natural20::MapRenderer.new(map).render
      expect(@fighter.available_movement(@battle)).to eq(30)
      action = @battle.action(@fighter, :move,
                              move_path: [[1, 6], [2, 6], [3, 6], [4, 6], [5, 6], [6, 6], [7, 6]])
      @battle.commit(action)
      expect(map.position_of(@fighter)).to eq([4, 6])
    end

    it 'handles the prone condition (crawling)' do
      @fighter.prone!
      movement = compute_actual_moves(@fighter, [[0, 6], [1, 6], [2, 6], [3, 6]], map, @battle, 6)
      expect(movement.movement).to eq([[0, 6], [1, 6]])
    end
  end
end
