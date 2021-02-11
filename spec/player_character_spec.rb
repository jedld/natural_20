# typed: false
require 'natural_20/player_character'

RSpec.describe Natural20::PlayerCharacter do
  let(:session) { Natural20::Session.new }

  context 'wizard' do
    before do
      @player = Natural20::PlayerCharacter.load(session, File.join('fixtures', 'high_elf_mage.yml'))
    end

    specify '#has_spells?' do
      expect(@player.has_spells?).to be
    end

    specify '#available_actions' do
      expect(@player.available_actions(session,
                                       @battle).map(&:to_s)).to eq ['Spell', 'Look', 'Attack', 'Move', 'Use item',
                                                                    'Interact', 'Ground interact', 'Inventory', 'Grapple', 'Drop grapple', 'Shove', 'Push']
    end

    specify '#spell_attack_modifier' do
      expect(@player.spell_attack_modifier).to eq(6)
    end

    specify '#ranged_spell_attack' do
      attack = @player.ranged_spell_attack!(@battle, 'firebolt')
      expect(attack.roller.roll_str).to eq('1d20+6')
    end

    context '#spell_slots' do
      specify 'return 1st level spell slots' do
        expect(@player.spell_slots(1)).to eq(2)
      end
    end

    context '#available_spells' do
      specify do
        expect(@player.available_spells(@battle).keys).to eq(['firebolt', "mage_armor"])
      end
    end
  end

  context 'fighter' do
    before do
      String.disable_colorization true
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

    context '#available_actions' do
      before do
        @battle = Natural20::Battle.new(session, nil)
        @battle.add(@player, :a)
        @player.reset_turn!(@battle)
      end
      specify do
        expect(@player.available_actions(session,
                                         @battle).map(&:to_s)).to eq ['Look', 'Attack', 'Attack', 'Attack', 'Move', 'Dash', 'Hide', 'Help', 'Dodge',
                                                                      'Use item', 'Interact', 'Inventory', 'Grapple', 'Shove', 'Push', 'Prone', 'Short rest', 'Second wind']
      end
      specify 'opportunity attacks' do
        expect(@player.available_actions(session,
                                         @battle, opportunity_attack: true).map(&:to_s)).to eq %w[Attack Attack]
        @battle.consume(@player, :reaction)
        expect(@player.available_actions(session,
                                         @battle, opportunity_attack: true).map(&:to_s)).to eq %w[]
      end
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
      roll = @player.perception_check!
      expect(roll.modifier).to eq(4)
      expect(roll.result).to eq(24)
    end

    specify '#dexterity_check!' do
      srand(1000)
      expect(@player.dexterity_check!.to_s).to eq('(20) + 5')
      expect(@player.dexterity_check!.result).to eq(13)
    end

    specify '#stealth_check!' do
      expect(@player.stealth_check!.to_s).to eq('(1) + 5')
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
      @player.unequip_all
      expect(@player.check_equip('light_crossbow')).to eq(:ok)
      @player.equip('light_crossbow', ignore_inventory: true)
      expect(@player.check_equip('studded_leather')).to eq(:ok)
      expect(@player.check_equip('scimitar')).to eq(:hands_full)
    end

    specify '#proficient_with_weapon?' do
      expect(@player.proficient_with_weapon?('rapier')).to be
      expect(@player.proficient_with_weapon?('longbow')).to be
    end

    specify '#proficient?' do
      expect(@player.proficient?('perception')).to be
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

    specify '#hit_die' do
      expect(@player.hit_die).to eq(10 => 1)
    end

    specify '#short_rest!' do
      srand(1000)
      Natural20::EventManager.standard_cli
      @player.take_damage!(damage: 4)
      expect(@player.hit_die).to eq(10 => 1)
      expect do
        @player.short_rest!(@battle)
      end.to change(@player, :hp).from(63).to(67)
      expect(@player.hit_die).to eq(10 => 0)
    end

    specify '#saving_throw!' do
      srand(1000)
      result = Natural20::Entity::ATTRIBUTE_TYPES.map do |attribute|
        @player.saving_throw!(attribute)
      end
      expect(result.map { |dr| dr.roller.roll_str }).to eq(['d20+4', 'd20+5', 'd20+6', 'd20+3', 'd20+1', 'd20+0'])
    end

    specify 'skill mods' do
      expect(@player.acrobatics_mod).to eq(8)
      expect(@player.arcana_mod).to eq(6)
    end
  end

  context 'rogue' do
    context 'halfling' do
      before do
        @player = Natural20::PlayerCharacter.load(session, File.join('fixtures', 'halfling_rogue.yml'))
      end

      specify '#languages' do
        expect(@player.languages).to eq(%w[common halfling thieves_cant])
      end

      # test to see if character is "glowing" because of equipment
      specify '#light_properties' do
        expect(@player.light_properties).to eq({
                                                 bright: 20.0,
                                                 dim: 20.0
                                               })
      end

      specify '#proficient?' do
        expect(@player.proficient?('longsword')).to be
      end
    end
    context 'elf' do
      before do
        @player = Natural20::PlayerCharacter.load(session, File.join('fixtures', 'elf_rogue.yml'))
      end

      specify '#languages' do
        expect(@player.languages).to eq(%w[common elvish thieves_cant])
      end

      # test to see if character is "glowing" because of equipment
      specify '#light_properties' do
        expect(@player.light_properties).to eq({
                                                 bright: 20.0,
                                                 dim: 20.0
                                               })
      end

      specify '#proficient?' do
        expect(@player.proficient?('longsword')).to be
      end
    end
  end
end
