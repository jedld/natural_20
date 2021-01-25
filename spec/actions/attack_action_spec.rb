# typed: false
RSpec.describe AttackAction do
  let(:session) { Natural20::Session.new }

  context do
    before do
      srand(1000)
      @battle_map = Natural20::BattleMap.new(session, 'fixtures/battle_sim')
      @battle = Natural20::Battle.new(session, @battle_map)
      @character = Natural20::PlayerCharacter.load(session, File.join('fixtures', 'high_elf_fighter.yml'))
      @npc = session.npc(:ogre)
      @npc2 = session.npc(:goblin)
    end
    context 'attack test' do
      before do
        String.disable_colorization true
        @battle.add(@character, :a, position: :spawn_point_1, token: 'G')
        @battle.add(@npc, :b, position: :spawn_point_2, token: 'g')

        @character.reset_turn!(@battle)
        @npc.reset_turn!(@battle)
      end

      it 'auto build' do
        cont = AttackAction.build(session, @character)
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
        expect(cont.source).to eq(@character)
        expect(cont.using).to eq('vicious_rapier')
      end

      specify 'unarmed attack' do
        Natural20::EventManager.standard_cli
        @battle_map.move_to!(@character, 0, 5)
        puts Natural20::MapRenderer.new(@battle_map).render
        action = AttackAction.build(session, @character).next.call(@npc).next.call('unarmed_attack').next.call
        expect do
          @battle.action!(action)
          @battle.commit(action)
        end.to change(@npc, :hp).from(59).to(57)
      end

      context 'versatile weapon' do
        it 'one handed attack' do
          @character.unequip(:longbow)
          expect(@character.equipped_items.map(&:name).sort).to eq(%i[shield studded_leather vicious_rapier])
          action = AttackAction.build(session, @character).next.call(@npc).next.call('spear').next.call
          action.resolve(session, @battle_map, battle: @battle)
          expect(action.result.first[:damage_roll]).to eq('1d6+3')
          @character.unequip(:vicious_rapier)
          action.resolve(session, @battle_map, battle: @battle)
          expect(action.result.first[:damage_roll]).to eq('1d8+3')
        end
      end

      specify 'range disadvantage' do
        @battle.add(@npc2, :b, position: [3, 3], token: 'O')
        @npc2.reset_turn!(@battle)
        Natural20::EventManager.standard_cli
        action = AttackAction.build(session, @character).next.call(@npc).next.call('longbow').next.call
        expect do
          @battle.action!(action)
          @battle.commit(action)
        end.to change(@npc, :hp).from(59).to(52)
      end
    end

    context 'unseen attacker' do
      before do
        @battle.add(@character, :a, position: :spawn_point_3, token: 'R')
        @character.reset_turn!(@battle)
        @guard = @battle_map.entity_at(5, 5)
        @action = AttackAction.build(session, @character).next.call(@guard).next.call('longbow').next.call
        srand(2000)
      end

      context 'attach from the dark' do
        specify '#compute_advantages_and_disadvantages' do
          puts Natural20::MapRenderer.new(@battle_map).render(line_of_sight: @guard)
          weapon = session.load_weapon('longbow')
          expect(@action.compute_advantages_and_disadvantages(@battle, @character, @guard,
                                                              weapon)).to eq([[:unseen_attacker], []])
        end

        it 'computes advantage' do
          Natural20::EventManager.standard_cli

          expect do
            @battle.action!(@action)
            @battle.commit(@action)
          end.to change { @guard.hp }.from(10).to(0)
        end
      end

      context 'when target is prone' do
        before do
          @battle_map.move_to!(@character, 2, 3)
          @guard.prone!
        end

        context 'ranged weapon' do
          let(:weapon) { session.load_weapon('longbow') }

          specify 'has range disadvantage' do
            expect(@action.compute_advantages_and_disadvantages(@battle, @character, @guard,
                                                                weapon)).to eq([[], [:target_is_prone_range]])
          end
        end

        context 'melee attack' do
          let(:weapon) { session.load_weapon('rapier') }
          specify 'has melee advantage' do
            expect(@action.compute_advantages_and_disadvantages(@battle, @character, @guard,
                                                                weapon)).to eq([[:target_is_prone], []])
          end
        end
      end

      context 'when attacker is prone' do
        before do
          @battle_map.move_to!(@character, 2, 3)
          @character.prone!
        end

        context 'ranged weapon' do
          let(:weapon) { session.load_weapon('longbow') }

          specify 'has range disadvantage' do
            expect(@action.compute_advantages_and_disadvantages(@battle, @character, @guard,
                                                                weapon)).to eq([[], [:prone]])
          end
        end

        context 'melee attack' do
          let(:weapon) { session.load_weapon('rapier') }
          specify 'has melee disadvantage' do
            expect(@action.compute_advantages_and_disadvantages(@battle, @character, @guard,
                                                                weapon)).to eq([[], [:prone]])
          end
        end
      end

      context 'attack while hiding' do
        let(:weapon) { session.load_weapon('longbow') }
        before do
          @battle_map.move_to!(@character, 2, 3)
          @character.hiding!(@battle, 20)
        end

        specify '#compute_advantages_and_disadvantages' do
          puts Natural20::MapRenderer.new(@battle_map).render(line_of_sight: @guard)
          expect(@action.compute_advantages_and_disadvantages(@battle, @character, @guard,
                                                              weapon)).to eq([[:unseen_attacker], []])
        end

        context 'bad at hiding' do
          before do
            @character.hiding!(@battle, 8)
          end

          specify '#compute_advantages_and_disadvantages' do
            puts Natural20::MapRenderer.new(@battle_map).render(line_of_sight: @guard)
            expect(@action.compute_advantages_and_disadvantages(@battle, @character, @guard,
                                                                weapon)).to eq([[], []])
          end
        end
      end
    end
  end

  context '#calculate_cover_ac' do
    before do
      @battle_map = Natural20::BattleMap.new(session, 'fixtures/battle_sim_objects')
      @map_renderer = Natural20::MapRenderer.new(@battle_map)
      @character = Natural20::PlayerCharacter.load(session, File.join('fixtures', 'high_elf_fighter.yml'))
      @npc2 = session.npc(:goblin)
      @battle_map.place(1, 2, @character, 'G')
      @battle_map.place(5, 2, @npc2, 'g')
      @action = AttackAction.build(session, @character).next.call(@npc2).next.call('longbow').next.call
      @action2 = AttackAction.build(session, @npc2).next.call(@character).next.call('longbow').next.call
    end

    it 'adjusts AC based on cover characteristics' do
      expect(@action.calculate_cover_ac(@battle_map, @npc2)).to eq 0
      expect(@action2.calculate_cover_ac(@battle_map, @character)).to eq 2
    end
  end
end
