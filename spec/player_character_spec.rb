require 'player_character'

RSpec.describe PlayerCharacter do
  let(:session) { Session.new }

  context 'fighter' do
    before do
      @fighter = PlayerCharacter.load(File.join('fixtures', 'high_elf_fighter.yml'))
    end

    it 'creates a player character' do
      expect(@fighter).to be
    end

    specify '#name' do
      expect(@fighter.name).to eq 'Gomerin'
    end

    specify '#str_mod' do
      expect(@fighter.str_mod).to eq 1
    end

    specify '#hp' do
      expect(@fighter.hp).to eq 67
    end

    specify '#passive_perception' do
      expect(@fighter.passive_perception).to eq 14
    end

    specify '#armor_class' do
      expect(@fighter.armor_class).to eq 21
    end

    specify '#armor_class' do
      expect(@fighter.speed).to eq 30
    end

    specify '#available_actions' do
      expect(@fighter.available_actions(session).map(&:to_s)).to eq ['Attack', 'Attack', 'Attack', 'Move', 'Use item', 'Interact', 'Inventory', 'Second wind']
    end

    specify '#to_h' do
      expect(@fighter.to_h).to eq({
                                    ability: { cha: 11, con: 16, dex: 20, int: 16, str: 12, wis: 12 },
                                    classes: { "fighter": 1 },
                                    hp: 67,
                                    name: 'Gomerin',
                                    passive: { insight: 11, investigation: 13, perception: 14 }
                                  })
    end

    specify '#usable_items' do
      expect(@fighter.usable_items).to eq([{ item: { consumable: true,
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
  end
end
