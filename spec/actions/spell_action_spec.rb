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
