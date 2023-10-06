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

      context 'two weapon fighting' do
        before do
          @character = Natural20::PlayerCharacter.load(session, File.join('fixtures', 'elf_rogue.yml'),
                                                       { equipped: %w[dagger dagger] })
          @npc = session.npc(:goblin)
          @battle.add(@character, :a, token: 'R', position: [0, 0])
          @battle.add(@npc, :b, token: 'g', position: [1, 0])
          @character.reset_turn!(@battle)
          @npc.reset_turn!(@battle)
        end

        it 'allows for two weapon fighting' do
          puts Natural20::MapRenderer.new(@battle_map).render
          expect(@character.available_actions(session, @battle).map(&:action_type)).to include(:attack)
          expect(@character.equipped_items.map(&:label)).to eq(%w[Dagger Dagger])
          action = AttackAction.build(session, @character).next.call(@npc).next.call('dagger').next.call
          @battle.action!(action)
          @battle.commit(action)
          expect(@character.available_actions(session, @battle).map(&:action_type)).to include(:attack)
        end
      end

      specify 'unarmed attack' do
        Natural20::EventManager.standard_cli
        @battle_map.move_to!(@character, 0, 5, @battle)
        srand(1000)
        puts Natural20::MapRenderer.new(@battle_map).render
        action = AttackAction.build(session, @character).next.call(@npc).next.call('unarmed_attack').next.call
        expect do
          @battle.action!(action)
          @battle.commit(action)
        end.to change(@npc, :hp).from(59).to(57)
      end

      specify '#compute_hit_probability' do
        @battle_map.move_to!(@character, 0, 5, @battle)
        puts Natural20::MapRenderer.new(@battle_map).render
        action = AttackAction.build(session, @character).next.call(@npc).next.call('unarmed_attack').next.call
        expect(action.compute_hit_probability(@battle).round(2)).to eq(0.55)
      end

      specify '#avg_damage' do
      @battle_map.move_to!(@character, 0, 5, @battle)
      puts Natural20::MapRenderer.new(@battle_map).render
      action = AttackAction.build(session, @character).next.call(@npc).next.call('unarmed_attack').next.call
      expect(action.avg_damage(@battle).round(2)).to eq(2)
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
        end.to change(@npc, :hp).from(59).to(49)
      end
    end

    context 'resistances and vulnerabilities' do
      before do
        Natural20::EventManager.standard_cli
        @npc = session.npc(:skeleton, overrides: { max_hp: 100 })
        @battle.add(@npc, :b, position: [1, 0])
        @battle.add(@character, :a, position: [2, 0])
      end

      context 'handle resistances and vulnerabilites' do
        specify 'attack with normal weapon' do
          srand(1000)
          expect do
            puts Natural20::MapRenderer.new(@battle_map, @battle).render
            @action = AttackAction.build(session, @character).next.call(@npc).next.call('dagger').next.call
            @action.resolve(session, @battle_map, battle: @battle)
            @battle.commit(@action)
          end.to change(@npc, :hp).from(100).to(87)
        end
        specify 'attack with vulnerable weapon' do
          srand(1000)
          expect do
            puts Natural20::MapRenderer.new(@battle_map, @battle).render
            @action = AttackAction.build(session, @character).next.call(@npc).next.call('light_hammer').next.call
            @action.resolve(session, @battle_map, battle: @battle)
            @battle.commit(@action)
          end.to change(@npc, :hp).from(100).to(82)
        end
      end
    end

    context 'unseen attacker' do
      before do
        @battle.add(@character, :a, position: :spawn_point_3, token: 'G')
        @character.reset_turn!(@battle)
        @guard = @battle_map.entity_at(5, 5)
        @action = AttackAction.build(session, @character).next.call(@guard).next.call('longbow').next.call
        srand(2000)
      end

      context 'attack from the dark' do
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
          @battle_map.move_to!(@character, 2, 3, @battle)
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
          @battle_map.move_to!(@character, 2, 3, @battle)
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
          @battle_map.move_to!(@character, 2, 3, @battle)
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

        context 'Naturally Stealthy' do
          before do
            @character2 = Natural20::PlayerCharacter.load(session, File.join('fixtures', 'halfling_rogue.yml'))
            @battle.add(@character2, :a, position: [1, 3])
            @battle_map.move_to!(@guard, 4, 3, @battle)
            @character2.hiding!(@battle, 20)
          end

          specify do
            expect(@character2.class_feature?('naturally_stealthy')).to be
          end

          specify '#compute_advantages_and_disadvantages' do
            puts Natural20::MapRenderer.new(@battle_map).render(line_of_sight: @guard)
            expect(@action.compute_advantages_and_disadvantages(@battle, @character2, @guard,
                                                                weapon)).to eq([[:unseen_attacker], []])
          end
        end
      end

      context 'pack_tactics' do
        before do
          @npc = session.npc(:wolf)
          @npc2 = session.npc(:wolf)
          @battle_map.move_to!(@character, 0, 5, @battle)
          @battle.add(@npc, :b, position: [1, 5])
          @battle.add(@npc2, :b, position: [0, 6])
        end

        specify '#compute_advantages_and_disadvantages' do
          puts Natural20::MapRenderer.new(@battle_map).render
          expect(@action.compute_advantages_and_disadvantages(@battle, @npc, @character,
                                                              @npc.npc_actions.first)).to eq([[:pack_tactics], []])
        end

        specify 'no pack tactics if no ally' do
          @battle_map.move_to!(@npc2, 2, 5, @battle)
          puts Natural20::MapRenderer.new(@battle_map).render
          expect(@action.compute_advantages_and_disadvantages(@battle, @npc, @character,
                                                              @npc.npc_actions.first)).to eq([[], []])
        end
      end
    end

    context 'attacking an unseen or invisible target' do
      before do
        Natural20::EventManager.standard_cli
        @character = Natural20::PlayerCharacter.load(session, File.join('fixtures', 'human_fighter.yml'))
        @goblin = session.npc(:goblin)
        @battle.add(@character, :a, position: [5, 0])
        @battle_map.place(5, 1, @goblin)
        @action = AttackAction.build(session, @character).next.call(@goblin).next.call('dagger').next.call
      end

      specify 'has disadvantage' do
        puts Natural20::MapRenderer.new(@battle_map).render
        expect(@action.compute_advantages_and_disadvantages(@battle, @character, @goblin,
                                                            'dagger')).to eq([[], [:invisible_attacker]])
      end

      specify 'can attack invisible' do
        @battle.action!(@action)
        @battle.commit(@action)
        expect(@action.result.last[:attack_roll].roller.disadvantage).to be
      end
    end

    context 'protection fighting style' do
      before do
        @npc = session.npc(:wolf)
        @character = Natural20::PlayerCharacter.load(session, File.join('fixtures', 'high_elf_fighter.yml'),
                                                     { class_features: ['protection'] })
        @character2 = Natural20::PlayerCharacter.load(session, File.join('fixtures', 'halfling_rogue.yml'))
        @battle.add(@character, :a, position: [0, 5])
        @battle.add(@character2, :a, position: [1, 5])
        @battle.add(@npc, :b, position: [1, 6])
        @character.reset_turn!(@battle)
        Natural20::EventManager.standard_cli
      end

      specify 'able to impose disadvantage on attack roll' do
        puts Natural20::MapRenderer.new(@battle_map).render
        expect(@character.class_feature?('protection')).to be
        expect(@character.shield_equipped?).to be
        action = AttackAction.build(session, @npc).next.call(@character2).next.call('Bite').next.call
        @battle.action!(action)
        @battle.commit(action)
        expect(action.advantage_mod).to eq(-1)
        expect(@character.total_reactions(@battle)).to eq(0)
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
