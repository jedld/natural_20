# typed: false
RSpec.describe Natural20::BattleMap do
  let(:session) { Natural20::Session.new }
  context 'map 1' do
    before do
      String.disable_colorization true
      @battle_map = Natural20::BattleMap.new(session, 'fixtures/battle_sim')
      @map_renderer = Natural20::MapRenderer.new(@battle_map)
      @fighter = Natural20::PlayerCharacter.load(session, File.join('fixtures', 'high_elf_fighter.yml'))
      @npc = session.npc(:goblin, name: 'grok')
      @battle_map.place(0, 1, @fighter, 'G')
    end

    specify '#size' do
      expect(@battle_map.size).to eq [6, 7]
    end

    specify '#render' do
      expect(@map_renderer.render).to eq "g···#·\n" +
                                         "G··##·\n" +
                                         "····#·\n" +
                                         "······\n" +
                                         "·##oo·\n" +
                                         "·····Î\n" +
                                         "······\n"

      @battle_map.place(2, 3, @npc, 'X')
      expect(@map_renderer.render(line_of_sight: @npc)).to eq "g··   \n" +
                                                              "G··## \n" +
                                                              "····# \n" +
                                                              "··g···\n" +
                                                              " ##oo·\n" +
                                                              "   ··Î\n" +
                                                              "    ··\n"
    end

    context '#place' do
      specify 'place tokens in the batlefield' do
        @battle_map.place(3, 3, @npc, 'g')
        expect(@map_renderer.render).to eq "g···#·\n" +
                                           "G··##·\n" +
                                           "····#·\n" +
                                           "···g··\n" +
                                           "·##oo·\n" +
                                           "·····Î\n" +
                                           "······\n"
      end
    end

    context '#remove' do
      specify 'remove tokens in the battlefield' do
        @battle_map.place(3, 3, @npc, 'g')
        @battle_map.remove(@npc)
        expect(@map_renderer.render).to eq "g···#·\n" +
                                           "G··##·\n" +
                                           "····#·\n" +
                                           "······\n" +
                                           "·##oo·\n" +
                                           "·····Î\n" +
                                           "······\n"
      end
    end

    # distance in squares
    specify '#distance' do
      @battle_map.place(3, 3, @npc, 'g')
      expect(@battle_map.distance(@npc, @fighter)).to eq(3)
    end

    specify '#valid_position?' do
      expect(@battle_map.valid_position?(6, 6)).to_not be
      expect(@battle_map.valid_position?(-1, 4)).to_not be
      expect(@battle_map.valid_position?(1, 4)).to_not be
      expect(@battle_map.valid_position?(1, 0)).to be
    end

    specify '#line_of_sight?' do
      expect(@battle_map.line_of_sight?(0, 0, 0, 1)).to be
      expect(@battle_map.line_of_sight?(0, 1, 0, 0)).to be
      expect(@battle_map.line_of_sight?(3, 0, 3, 2)).to_not be
      expect(@battle_map.line_of_sight?(3, 2, 3, 0)).to_not be
      expect(@battle_map.line_of_sight?(0, 0, 3, 0)).to be
      expect(@battle_map.line_of_sight?(0, 0, 5, 0)).to_not be
      expect(@battle_map.line_of_sight?(5, 0, 0, 0)).to_not be
      expect(@battle_map.line_of_sight?(0, 0, 2, 2)).to be
      expect(@battle_map.line_of_sight?(2, 0, 4, 2)).to_not be
      expect(@battle_map.line_of_sight?(4, 2, 2, 0)).to_not be
      expect(@battle_map.line_of_sight?(1, 5, 3, 0)).to_not be
      expect(@battle_map.line_of_sight?(0, 0, 5, 5)).to be
      expect(@battle_map.line_of_sight?(2, 3, 2, 4)).to be
      expect(@battle_map.line_of_sight?(2, 3, 1, 4)).to be
      expect(@battle_map.line_of_sight?(3, 2, 3, 1)).to be
      expect(@battle_map.line_of_sight?(2, 3, 5, 1)).to_not be
    end

    specify '#spawn_points' do
      expect(@battle_map.spawn_points).to eq({
                                               'spawn_point_1' => { location: [2, 3] },
                                               'spawn_point_2' => { location: [1, 5] },
                                               'spawn_point_3' => { location: [5, 0] },
                                               'spawn_point_4' => { location: [5, 3] }
                                             })
    end

    # context "line of sight corridors test" do
    #   before do
    #     @battle_map = Natural20::BattleMap.new(session, 'fixtures/corridors')
    #     @map_renderer = Natural20::MapRenderer.new(@battle_map)
    #   end

    #   it "handles corrideros properly" do
    #     @battle_map.place(0, 5, @npc, 'g')
    #     expect(@map_renderer.render(line_of_sight: @npc)).to eq ""
    #   end
    # end
  end

  context 'other sizes test' do
    before do
      @battle_map = Natural20::BattleMap.new(session, 'fixtures/battle_sim_3')
      @map_renderer = Natural20::MapRenderer.new(@battle_map)
      @battle = Natural20::Battle.new(session, @battle_map)
      @fighter = Natural20::PlayerCharacter.load(session, File.join('fixtures', 'high_elf_fighter.yml'))
      @npc = session.npc(:ogre, name: 'grok')
      @goblin = session.npc(:goblin, name: 'dave')
      @battle_map.place(0, 5, @fighter, 'G')
      @battle_map.place(0, 1, @npc)
      @battle.add(@fighter, :a)
      @battle.add(@npc, :b)
    end

    it 'renders token sizes correctly' do
      expect(@map_renderer.render).to eq(
        "#######\n" +
        "O┐····#\n" +
        "└┘····#\n" +
        "####··#\n" +
        "······#\n" +
        "G·····#\n" +
        "·······\n"
      )
    end

    specify '#placeable?' do
      @battle.add(@goblin, :b)
      @battle_map.place(1, 5, @goblin, 'g')
      puts @map_renderer.render
      expect(@battle_map.placeable?(@npc, 1, 4)).to be
    end
  end

  context 'other objects' do
    before do
      String.disable_colorization true
      @battle_map = Natural20::BattleMap.new(session, 'fixtures/battle_sim_objects')
      @battle = Natural20::Battle.new(session, @battle_map)
      @map_renderer = Natural20::MapRenderer.new(@battle_map)
      @fighter = Natural20::PlayerCharacter.load(session, File.join('fixtures', 'high_elf_fighter.yml'))
      @rogue = Natural20::PlayerCharacter.load(session, File.join('fixtures', 'halfling_rogue.yml'))
      @battle_map.place(0, 5, @fighter, 'G')
      @battle_map.place(2, 5, @rogue, 'R')
    end

    it 'renders door objects correctly' do
      expect(@map_renderer.render(line_of_sight: @fighter)).to eq("        \n" +
        "        \n" +
        "        \n" +
        "        \n" +
        "#=#     \n" +
        "G`R^^g^#\n" +
        "··▓^·▓▓^\n" +
        "####    \n")

      door = @battle_map.object_at(1, 4)
      door.open!

      expect(@map_renderer.render(line_of_sight: @fighter)).to eq("   #    \n" +
        "  ^     \n" +
        "  o     \n" +
        " ·#     \n" +
        "#-#     \n" +
        "G`R^^g^#\n" +
        "··▓^·▓▓^\n" +
        "####    \n")
    end

    specify '#wall?' do
      expect(@battle_map.wall?(0, 3)).to be
    end

    specify '#passable?' do
      door = @battle_map.object_at(1, 4)
      door.close!
      expect(@battle_map.passable?(@fighter, 1, 4)).to_not be
    end

    specify '#objects_near' do
      door = @battle_map.object_at(1, 4)
      goblin = @battle_map.entity_at(1, 5)
      expect(goblin.dead?).to be
      expect(@battle_map.objects_near(@fighter).size).to eq(2)
      expect(@battle_map.objects_near(@fighter)).to eq([door, goblin])
    end

    specify '#squares_in_path' do
      expect(@battle_map.squares_in_path(1, 2, 3, 2)).to eq([[1, 2], [2, 2]])
      expect(@battle_map.line_of_sight?(1, 2, 3, 2)).to eq([[:half, [2, 2]]])
    end

    specify '#perception_on' do
      goblin = @battle_map.entity_at(1, 5)
      expect(@battle_map.perception_on(goblin, @fighter,
                                       20)).to eq(['(perception) Dead Goblin!',
                                                   '(perception) In his hand is a wooden door key.', 'Remnants of a dead goblin, corpse is still fresh', '(in goblin) Stay away this goblin is a traitor'])
      # Check for language barrier
      expect(@battle_map.perception_on(goblin, @rogue,
                                       20)).to eq(['(perception) Dead Goblin!',
                                                   '(perception) In his hand is a wooden door key.', 'Remnants of a dead goblin, corpse is still fresh', '(in goblin) ???'])

      # Check for conditional notes
      expect(goblin.list_notes(@fighter, 20)).to include '(perception) In his hand is a wooden door key.'
      goblin.deduct_item('wooden_door_key')
      expect(goblin.list_notes(@fighter, 20)).to_not include '(perception) In his hand is a wooden door key.'
    end

    specify '#highlight' do
      expect(@battle_map.highlight(@fighter, 20).values).to eq([['(perception) Dead Goblin!']])
    end

    specify '#perception_on_area' do
      expect(@battle_map.perception_on_area(3, 5, @fighter,
                                            20)).to eq(['A pool of stinky water', 'A vile stench fills this room'])
      expect(@battle_map.perception_on_area(4, 5, @fighter,
                                            20)).to eq(['A pool of stinky water', 'A vile stench fills this room'])
      expect(@battle_map.perception_on_area(1, 5, @fighter, 20)).to eq(['A vile stench fills this room'])
    end

    specify '#difficult_terrain?' do
      expect(@battle_map.difficult_terrain?(@fighter, 3, 5, nil)).to be
    end

    context 'battle status overrides' do
      let(:npc) { @battle_map.entity_at(5, 5) }

      it 'has the correct statuses' do
        srand(1000)
        @battle.add(npc, :b)
        npc.reset_turn!(@battle)
        expect(npc.hiding?(@battle)).to be
        expect(@battle.entity_state_for(npc)).to eq({
                                                      action: 1,
                                                      bonus_action: 1,
                                                      controller: nil,
                                                      free_object_interaction: 1,
                                                      active_perception: 0,
                                                      active_perception_disadvantage: 0,
                                                      group: :b,
                                                      movement: 30,
                                                      reaction: 1,
                                                      statuses: Set[:hiding],
                                                      stealth: 26,
                                                      two_weapon: nil,
                                                      target_effect: {}
                                                    })
      end
    end
  end

  context 'environment lighting' do
    before do
      @battle_map = Natural20::BattleMap.new(session, 'fixtures/battle_sim_objects')
    end

    it 'generates static light map' do
    end
  end

  context 'map 2' do
    before do
      String.disable_colorization true
      @battle_map = Natural20::BattleMap.new(session, 'fixtures/game_map_sample')
      @map_renderer = Natural20::MapRenderer.new(@battle_map)
    end

    specify do
      expect(@battle_map.object_at(11, 1).token).to eq(['o'])
      expect(@map_renderer.send(:object_token, 11, 1)).to eq('o')
      expect(@map_renderer.render).to eq(
        "☐···\\\/····║·g··\n" +
        "····└┘····#oo··\n" +
        "###··####=#··O┐\n" +
        "··║··#g^^g#··└┘\n" +
        "·#####^^g☐#··oo\n" +
        "·····║^^og#····\n" +
        "####=#########=\n" +
        "··#·`·^Ý^<║···$\n" +
        "··║···^^^<#··$·\n"
      )
    end
  end
end
