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
end
