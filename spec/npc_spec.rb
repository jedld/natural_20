# typed: false
require 'natural_20/npc'

RSpec.describe Natural20::Npc do
  let(:session) do
    Natural20::Session.new
  end

  context 'skeleton npc' do
    before do
      @npc = session.npc(:skeleton)
    end

    specify '#damage_vulnerabilities' do
      expect(@npc.damage_vulnerabilities).to eq(['bludgeoning'])
    end
  end

  context 'bat npc' do
    before do
      @npc = session.npc(:bat, name: 'Screech')
    end

    specify '#speed' do
      expect(@npc.speed).to eq 5
    end

    specify 'flying' do
      @npc.fly!
      expect(@npc.speed).to eq 30
      expect(@npc.flying?).to be
    end

    specify '#can_fly?' do
      expect(@npc.can_fly?).to be
    end
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
      expect(@npc.equipped_items.map(&:name)).to eq(%i[scimitar shortbow leather_armor shield])
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
      expect(@npc.available_actions(session, nil).size).to eq 9
      expect(@npc.available_actions(session, nil).map(&:name)).to eq ["attack", "attack", "look", "move", "grapple", "use_item", "interact", "ground_interact", "inventory"]
    end

    specify '#hit_die' do
      expect(@npc.hit_die).to eq(6 => 2)
    end

    specify '#short_rest!' do
      srand(1000)
      Natural20::EventManager.standard_cli
      @npc.take_damage!(4)
      expect(@npc.hit_die).to eq(6 => 2)
      expect do
        @npc.short_rest!(@battle)
      end.to change(@npc, :hp).from(3).to(7)
      expect(@npc.hit_die).to eq(6 => 1)
    end

    specify '#saving_throw!' do
      srand(1000)
      result = Natural20::Entity::ATTRIBUTE_TYPES.map do |attribute|
        @npc.saving_throw!(attribute)
      end
      expect(result.map { |dr| dr.roller.roll_str }).to eq(['d20-1', 'd20+2', 'd20+0', 'd20+0', 'd20-1', 'd20-1'])
    end

    specify '#stealth_check!' do
      roll = @npc.stealth_check!(@battle)
      expect(roll.roller.roll_str).to eq('1d20+6')
    end

    specify '#apply_effect' do
      expect(@npc.apply_effect('status:prone')).to eq({ battle: nil, source: @npc, type: :prone, flavor: nil })
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
      expect(@npc.available_actions(session, nil).size).to eq 9
      expect(@npc.available_actions(session, nil).map(&:name)).to eq ["attack", "attack", "look", "move", "grapple", "use_item", "interact", "ground_interact", "inventory"]
      first_attack = @npc.available_actions(session, @battle).select { |a| a.name == 'attack' }.first
      first_attack.target = @fighter
      @battle.action!(first_attack)
      @battle.commit(first_attack)

      # multiattack should still allow for one more attack
      expect(@npc.available_actions(session, @battle).map(&:name)).to eq ["attack", "look", "move", "interact", "inventory"]
    end
  end
end
