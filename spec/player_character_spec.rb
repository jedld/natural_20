# typed: false
require 'natural_20/player_character'

RSpec.describe Natural20::PlayerCharacter do
  let(:session) { Natural20::Session.new }

  context 'fighter' do
    before do
      @player = Natural20::PlayerCharacter.load(session, File.join('fixtures', 'high_elf_fighter.yml'))
      @player2 = Natural20::PlayerCharacter.load(session, File.join('fixtures', 'halfling_rogue.yml'))
    end

    it 'creates a player character' do
      expect(@player).to be
    end

    specify '#name' do
      expect(@player.name).to eq 'Gomerin'
    end

    specify '#str_mod' do
      expect(@player.str_mod).to eq 1
    end

    specify '#hp' do
      expect(@player.hp).to eq 67
    end

    specify '#passive_perception' do
      expect(@player.passive_perception).to eq 14
    end

    specify '#standing_jump_distance' do
      expect(@player.standing_jump_distance).to eq 6
      expect(@player2.standing_jump_distance).to eq 5
    end

    specify '#long_jump_distance' do
      expect(@player.long_jump_distance).to eq 12
      expect(@player2.long_jump_distance).to eq 11
    end

    specify '#armor_class' do
      expect(@player.armor_class).to eq 19
    end

    specify '#armor_class' do
      expect(@player.speed).to eq 30
    end

    specify '#available_actions' do
      expect(@player.available_actions(session).map(&:to_s)).to eq ['Look', 'Attack', 'Attack', 'Attack', 'Move',
                                                                    'Use item', 'Interact', 'Ground interact', 'Inventory', 'Grapple', 'Drop grapple', 'Second wind']
    end

    specify '#to_h' do
      expect(@player.to_h).to eq({
                                   ability: { cha: 11, con: 16, dex: 20, int: 16, str: 12, wis: 12 },
                                   classes: { "fighter": 1 },
                                   hp: 67,
                                   name: 'Gomerin',
                                   passive: { insight: 11, investigation: 13, perception: 14 }
                                 })
    end

    specify '#usable_items' do
      expect(@player.usable_items).to eq([{ item: { consumable: true,
                                                    hp_regained: '2d4+2',
                                                    item_class: 'ItemLibrary::HealingPotion',
                                                    name: 'Potion of Healing',
                                                    type: 'potion',
                                                    usable: true },
                                            label: 'Potion of Healing',
                                            name: 'healing_potion',
                                            consumable: true,
                                            qty: 1 }])
    end

    specify '#inventory_weight' do
      expect(@player.inventory_weight).to eq(30.0)
    end

    specify '#carry_capacity' do
      expect(@player.carry_capacity).to eq(180.0)
    end

    specify '#perception_check!' do
      srand(1000)
      expect(@player.perception_check!.result).to eq(24)
    end

    specify '#dexterity_check!' do
      srand(1000)
      expect(@player.dexterity_check!.to_s).to eq('(20) + 5')
      expect(@player.dexterity_check!.result).to eq(13)
    end

    specify '#acrobatics_check!' do
      srand(1000)
      expect(@player.acrobatics_check!.to_s).to eq('(20) + 8')
      expect(@player.acrobatics_check!.result).to eq(16)
    end

    specify '#athletics_check!' do
      srand(1000)
      expect(@player.athletics_check!.to_s).to eq('(20) + 4')
      expect(@player.athletics_check!.result).to eq(12)
    end

    specify '#languages' do
      expect(@player.languages).to eq(%w[abyssal celestial common common elvish elvish goblin])
    end

    specify '#darkvision?' do
      expect(@player.darkvision?(60)).to be
    end

    specify '#check_equip' do
      expect(@player.check_equip('scimitar')).to eq(:hands_full)
      expect(@player.check_equip('studded_leather')).to eq(:armor_equipped)
    end

    context '#take_damage!' do
      specify 'unconscious' do
        @player.take_damage!(damage: Natural20::DieRoll.new([20], 80))
        expect(@player.unconscious?).to be
        expect(@player.dead?).to_not be
      end

      specify 'healing should revive unconscious entity' do
        @player.take_damage!(damage: Natural20::DieRoll.new([20], 80))
        expect(@player.unconscious?).to be
        @player.heal!(10)
        expect(@player.unconscious?).to_not be
      end

      specify 'lethal damage' do
        @player.take_damage!(damage: Natural20::DieRoll.new([20], 200))
        expect(@player.dead?).to be
      end
    end
  end

  context 'rogue' do
    before do
      @player = Natural20::PlayerCharacter.load(session, File.join('fixtures', 'halfling_rogue.yml'))
    end

    specify '#languages' do
      expect(@player.languages).to eq(%w[common halfling thieves_cant])
    end
  end
end