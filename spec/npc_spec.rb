# typed: false
require 'natural_20/npc'

RSpec.describe Natural20::Npc do
  let(:session) do
    Natural20::Session.new
  end

  context 'goblin npc' do
    before do
      @npc = session.npc(:goblin, name: 'Spark')
    end

    specify '#darkvision?' do
      expect(@npc.darkvision?(60)).to be
    end

    specify '#hp' do
      expect(@npc.hp).to be_between 2, 12
    end

    specify '#name' do
      expect(@npc.name).to eq 'Spark'
    end

    specify '#armor_class' do
      expect(@npc.armor_class).to eq 15
    end

    specify '#passive_perception' do
      expect(@npc.passive_perception).to eq 9
    end

    specify '#equipped_items' do
      expect(@npc.equipped_items.map(&:name)).to eq(%i[scimitar shortbow])
    end

    specify '#unequip' do
      @npc.unequip('scimitar')
      expect(@npc.equipped?('scimitar')).to_not be
      expect(@npc.item_count('scimitar').positive?).to be
    end

    specify '#equipped' do
      @npc.unequip('scimitar')
      expect(@npc.equipped?('scimitar')).to_not be
      @npc.equip('scimitar')
      expect(@npc.equipped?('scimitar')).to be
    end

    specify '#available_actions' do
      expect(@npc.available_actions(session, nil).size).to eq 5
      expect(@npc.available_actions(session, nil).map(&:name)).to eq %w[attack attack look move grapple]
    end

    specify '#hit_die' do
      expect(@npc.hit_die).to eq(6 => 2)
    end

    specify "#short_rest!" do
      srand(1000)
      Natural20::EventManager.standard_cli
      @npc.take_damage!(damage: 4)
      expect(@npc.hit_die).to eq(6 => 2)
      expect {
        @npc.short_rest!(@battle)
      }.to change(@npc, :hp).from(3).to(7)
      expect(@npc.hit_die).to eq(6 => 1)
    end
  end

  context 'owlbear npc' do
    before do
      @npc = session.npc(:owlbear, name: 'Grunt')
      @battle = Natural20::Battle.new(session, @map)
      @fighter = Natural20::PlayerCharacter.load(session, File.join('fixtures', 'high_elf_fighter.yml'))
      @battle.add(@fighter, :a, position: :spawn_point_1, token: 'G')
      @battle.add(@npc, :a, position: :spawn_point_2, token: 'G')
      @npc.reset_turn!(@battle)
      @fighter.reset_turn!(@battle)
      @battle.start
    end

    specify '#darkvision?' do
      expect(@npc.darkvision?(60)).to be
    end

    specify '#available actions' do
      expect(@npc.available_actions(session, nil).size).to eq 5
      expect(@npc.available_actions(session, nil).map(&:name)).to eq %w[attack attack look move grapple]
      first_attack = @npc.available_actions(session, @battle).select { |a| a.name == 'attack' }.first
      first_attack.target = @fighter
      @battle.action!(first_attack)
      @battle.commit(first_attack)
      expect(@npc.available_actions(session, @battle).map(&:name)).to eq %w[look move]
    end
  end
end
