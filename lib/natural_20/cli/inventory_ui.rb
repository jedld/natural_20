module Natural20::InventoryUI
  include Natural20::Weapons

  def character_sheet(entity)
    puts t('character_sheet.name', name: entity.name)
    puts t('character_sheet.level', level: entity.level)
    puts t('character_sheet.class', name: entity.class_properties.keys.join(','))
    puts ' str   dex   con   int   wis   cha'
    puts ' ----  ----  ----  ----  ----  ---- '
    puts "|#{entity.all_ability_scores.map { |s| " #{s} " }.join('||')}|"
    puts "|#{entity.all_ability_mods.map { |s| " +#{s} " }.join('||')}|"
    puts ' ----  ----  ----  ----  ----  ----'
    puts t('character_sheet.race', race: entity.race.humanize)
    puts t('character_sheet.hp', current: entity.hp, max: entity.max_hp)
    puts t('character_sheet.ac', ac: entity.armor_class)
    puts t('character_sheet.languages')
    entity.languages.each do |lang|
      puts "  #{t("language.#{lang}")}"
    end
  end

  # @param entity [Natural20::Entity]
  def inventory_ui(entity)
    begin
      character_sheet(entity)
      item_inventory_choice = prompt.select(
        t('character_sheet.inventory', weight: entity.inventory_weight,
                                       carry_capacity: entity.carry_capacity), per_page: 20
      ) do |menu|
        entity.equipped_items.each do |m|
          proficient_str = ''
          proficient_str = '(not proficient)'.colorize(:red) if m.subtype == 'weapon' && !entity.proficient_with_weapon?(m)
          proficient_str = '(not proficient)'.colorize(:red) if %w[armor
                                                    shield].include?(m.type) && !entity.proficient_with_armor?(m.name)
          menu.choice "#{m.label} (equipped) #{proficient_str}", m
        end
        entity.inventory.each do |m|
          menu.choice "#{m.label} x #{m.qty}", m
        end
        menu.choice 'Back', :back
      end

      return nil if item_inventory_choice == :back

      weapon_details = session.load_weapon(item_inventory_choice.name)
      if weapon_details
        puts ' '
        puts '-------'
        puts (weapon_details[:label] || weapon_details[:name]).colorize(:blue)
        puts "Damage Stats: to Hit +#{entity.attack_roll_mod(weapon_details)}. #{damage_modifier(entity,
                                                                                                 weapon_details)} #{weapon_details[:damage_type]} Damage"
        puts "Proficiency: #{entity.proficient_with_weapon?(weapon_details) ? t(:yes) : t(:no)}"
        puts 'Properties:'
        weapon_details[:properties]&.each do |p|
          puts "  #{t("object.properties.#{p}")}"
        end
        puts weapon_details[:description] || ''
      end

      if item_inventory_choice.equipped
        choice = prompt.select(item_inventory_choice.label) do |menu|
          menu.choice t(:unequip), :unequip
          menu.choice t(:back), :back
        end

        next if choice == :back

        if battle.combat? && weapon_details[:type] == 'armor'
          puts t('inventory.cannot_change_armor_combat')
          next
        end
        entity.unequip(item_inventory_choice.name)
      else
        choice = prompt.select(item_inventory_choice.label) do |menu|
          reasons = entity.check_equip(item_inventory_choice.name)
          if reasons == :ok || reasons != :unequippable
            if reasons == :ok
              menu.choice 'Equip', :equip
            else
              menu.choice 'Equip', :equip, disabled: t("object.equip_problem.#{reasons}")
            end
          end
          menu.choice t(:drop), :drop if map.ground_at(*map.entity_or_object_pos(entity))
          menu.choice 'Back', :back
        end

        case choice
        when :back
          next
        when :drop # drop item to the ground
          qty = how_many?(item_inventory_choice)
          entity.drop_items!(battle, [[item_inventory_choice, qty]])
        when :equip
          if battle.combat? && weapon_details[:type] == 'armor'
            puts t('inventory.cannot_change_armor_combat')
            next
          end
          entity.equip(item_inventory_choice.name)
        end
      end
    end while true
  end

  def how_many?(item_inventory_choice)
    if item_inventory_choice.qty > 1
      item_count = item_inventory_choice.qty
      m = item_inventory_choice
      item_label = t("object.#{m.label}", default: m.label)
      count = prompt.ask(t('inventory.how_many', item_label: item_label, item_count: item_count),
                         default: item_count) do |q|
        q.in "1-#{item_count}"
        q.messages[:range?] = '%{value} out of expected range %{in}'
      end
      count.to_i
    else
      1
    end
  end
end
