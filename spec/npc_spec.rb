require 'npc'

RSpec.describe Npc do
  let(:session) do
    Session.new
  end

  context 'goblen npc' do
    before do
      @npc = Npc.new(:goblin, name: 'Spark')
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

    specify '#available_actions' do
      expect(@npc.available_actions(session).size).to eq 3
      expect(@npc.available_actions(session).map(&:name)).to eq %w[attack attack end]
    end
  end

  context 'owlbear npc' do
    before do
      @npc = Npc.new(:owlbear, name: 'Grunt')
      @battle = Battle.new(session, @map)
      @fighter = PlayerCharacter.load(File.join('fixtures', 'high_elf_fighter.yml'))
      @battle.add(@fighter, :a, position: :spawn_point_1, token: 'G')
      @battle.add(@npc, :a, position: :spawn_point_2, token: 'G')
      @npc.reset_turn!(@battle)
      @fighter.reset_turn!(@battle)
      @battle.start
    end

    specify '#available actions' do
      expect(@npc.available_actions(session).size).to eq 3
      expect(@npc.available_actions(session).map(&:name)).to eq %w[attack attack end]
      first_attack = @npc.available_actions(session, @battle).select { |a| a.name == 'attack' }.first
      first_attack.target = @fighter
      @battle.action!(first_attack)
      @battle.commit(first_attack)
      expect(@npc.available_actions(session, @battle).map(&:name)).to eq %w[attack end]
    end
  end
end
