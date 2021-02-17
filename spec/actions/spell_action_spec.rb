# typed: false
RSpec.describe SpellAction do
  let(:session) { Natural20::Session.new }
  let(:entity) { Natural20::PlayerCharacter.load(session, File.join('fixtures', 'high_elf_mage.yml')) }

  before do
    srand(2001)
    Natural20::EventManager.standard_cli
    @battle_map = Natural20::BattleMap.new(session, 'fixtures/battle_sim_objects')
    @battle = Natural20::Battle.new(session, @battle_map)
    @npc = @battle_map.entity_at(5, 5)
    @battle.add(entity, :a, position: [0, 5])

    entity.reset_turn!(@battle)
  end

  context 'firebolt' do
    specify 'resolve and apply' do
      expect(@npc.hp).to eq(8)
      puts Natural20::MapRenderer.new(@battle_map).render
      action = SpellAction.build(session, entity).next.call('firebolt').next.call(@npc).next.call
      action.resolve(session, @battle_map, battle: @battle)
      expect(action.result.map { |s| s[:type] }).to eq([:spell_damage])
      @battle.commit(action)
      expect(@npc.hp).to eq(0)
    end
  end

  context 'shocking grasp' do
    before do
      @npc = session.npc(:skeleton)
      @battle.add(@npc, :b, position: [0, 6])
      @npc.reset_turn!(@battle)
    end

    specify do
      srand(1001)
      puts Natural20::MapRenderer.new(@battle_map).render
      action = SpellAction.build(session, entity).next.call('shocking_grasp').next.call(@npc).next.call
      action.resolve(session, @battle_map, battle: @battle)
      expect(action.result.map { |s| s[:type] }).to eq(%i[spell_damage shocking_grasp])
      expect(@npc.has_reaction?(@battle)).to be
      expect { @battle.commit(action) }.to change(@npc, :hp).from(13).to(11)
      expect(@npc.has_reaction?(@battle)).to_not be
    end
  end

  context 'ray of frost' do
    before do
      @npc = session.npc(:skeleton)
      @battle.add(@npc, :b, position: [0, 6])
      @npc.reset_turn!(@battle)
    end

    specify do
      srand(1001)
      puts Natural20::MapRenderer.new(@battle_map).render
      action = SpellAction.build(session, entity).next.call('ray_of_frost').next.call(@npc).next.call
      action.resolve(session, @battle_map, battle: @battle)
      expect(action.result.map { |s| s[:type] }).to eq(%i[spell_damage ray_of_frost])
      expect { @battle.commit(action) }.to change(@npc, :hp).from(13).to(7)
      expect(@npc.speed).to eq(20)
      entity.reset_turn!(@battle)
      expect(@npc.speed).to eq(30)
    end
  end

  context 'chill touch' do
    specify 'resolve and apply' do
      puts Natural20::MapRenderer.new(@battle_map).render
      action = SpellAction.build(session, entity).next.call('chill_touch').next.call(@npc).next.call
      action.resolve(session, @battle_map, battle: @battle)
      expect(action.result.map { |s| s[:type] }).to eq(%i[spell_damage chill_touch])
      expect { @battle.commit(action) }.to change(@npc, :hp).from(8).to(3)
      expect(@npc.has_spell_effect?(:chill_touch)).to be

      # target cannot heal until effect ends
      expect do
        @npc.heal!(100)
      end.to_not change(@npc, :hp)

      # drop effect until next turn
      entity.reset_turn!(@battle)
      expect do
        @npc.heal!(100)
      end.to change(@npc, :hp)
    end

    context 'applies disadvantage on undead' do
      include Natural20::Weapons

      before do
        @npc = session.npc(:skeleton)
        @battle.add(@npc, :b, position: [5, 5])
      end
      specify do
        puts Natural20::MapRenderer.new(@battle_map).render
        action = SpellAction.build(session, entity).next.call('chill_touch').next.call(@npc).next.call
        action.resolve(session, @battle_map, battle: @battle)
        expect { @battle.commit(action) }.to change(@npc, :hp).from(13).to(8)
        expect(target_advantage_condition(@battle, @npc, entity, nil)).to eq([-1, [[], [:chill_touch_disadvantage]]])
      end
    end
  end

  context "expeditious_retreat" do
    specify do

      @action = SpellAction.build(session, entity).next.call('expeditious_retreat').next.call
      @action.resolve(session, @battle_map, battle: @battle)
      expect(@action.result.map { |s| s[:type] }).to eq([:expeditious_retreat])
      @battle.commit(@action)
      expect(entity.available_actions(session, @battle).map(&:action_type)).to include :dash_bonus
    end
  end

  context 'mage armor' do
    before do
      expect(entity.armor_class).to eq(12)
      @action = SpellAction.build(session, entity).next.call('mage_armor').next.call(entity).next.call
      @action.resolve(session, @battle_map, battle: @battle)
      expect(@action.result.map { |s| s[:type] }).to eq([:mage_armor])
      @battle.commit(@action)
    end

    specify 'resolve and apply' do
      expect(entity.armor_class).to eq(15)
      expect(entity.dismiss_effect!(@action.spell_action).positive?).to be
      expect(entity.armor_class).to eq(12)
    end

    specify 'equip armor cancels effect' do
      expect(entity.armor_class).to eq(15)
      entity.equip('studded_leather', ignore_inventory: true)
      expect(entity.armor_class).to eq(12)
    end

    context 'shield' do
      specify do
        expect do
          @action = SpellAction.build(session, entity).next.call('shield').next.call
          @action.resolve(session, @battle_map, battle: @battle)
          @battle.commit(@action)
        end.to change(entity, :armor_class).from(15).to(20)
      end

      specify 'auto cast shield reaction' do
        expect do
          entity.reset_turn!(@battle)
          action = AttackAction.build(session, @npc).next.call(entity).next.call('Shortbow').next.call
          action.resolve(session, @battle_map, battle: @battle)
          @battle.commit(@action)
        end.to change(entity, :armor_class).from(15).to(20)
        expect do
          entity.reset_turn!(@battle)
        end.to change(entity, :armor_class).from(20).to(15)
      end

      context 'completely deflects magic missle' do
        let(:entity_2) { Natural20::PlayerCharacter.load(session, File.join('fixtures', 'high_elf_mage.yml')) }
        before do
          @battle.add(entity_2, :b, position: [3, 5], token: 'Q')
          entity_2.reset_turn!(@battle)
        end

        specify do
          puts Natural20::MapRenderer.new(@battle_map).render
          expect do
            action = SpellAction.build(session,
                                       entity_2).next.call('magic_missile').next.call([entity, entity,
                                                                                       entity]).next.call
            action.resolve(session, @battle_map, battle: @battle)
            @battle.commit(action)
          end.to_not change(entity, :hp)
        end
      end
    end
  end

  context 'magic missile' do
    specify do
      expect(@npc.hp).to eq(8)
      action = SpellAction.build(session, entity).next.call('magic_missile').next.call([@npc, @npc, @npc]).next.call
      action.resolve(session, @battle_map, battle: @battle)
      expect(action.result.map { |s| s[:type] }).to eq(%i[spell_damage spell_damage spell_damage])
      @battle.commit(action)
      expect(@npc.hp).to eq(0)
    end
  end

  context 'true strike' do
    include Natural20::Weapons

    before do
      @npc = session.npc(:skeleton)
      @battle.add(@npc, :b, position: [0, 6])
      @npc.reset_turn!(@battle)

      @action = SpellAction.build(session, entity).next.call('true_strike').next.call(@npc).next.call
      @action.resolve(session, @battle_map, battle: @battle)
      expect(@action.result.map { |s| s[:type] }).to eq([:true_strike])
      @battle.commit(@action)
    end

    specify do
      entity.reset_turn!(@battle)
      conditions = target_advantage_condition(@battle, entity, @npc, @action.spell)
      expect(conditions).to eq([1, [[:true_strike_advantage], []]])
    end
  end
end
