module Natural20::FighterBuilder
  def fighter_builder
    @class_values ||= {
      attributes: [],
      saving_throw_proficiencies: %w[strength constitution],
      equipped: [],
      inventory: []
    }

    fighter_features = %w[archery defense dueling great_weapon_fighting protection two_weapon_fighting]
    @class_values[:attributes] << prompt.select(t('builder.fighter.select_fighting_style')) do |q|
      fighter_features.each do |style|
        q.choice t("builder.fighter.#{style}"), style
      end
    end

    starting_equipment = []
    starting_equipment << prompt.select(t('builder.fighter.select_starting_weapon')) do |q|
      q.choice t('object.chain_mail'), :chain_mail
      q.choice t('object.longbow_and_arrows'), :longbow_and_arrows
    end

    starting_equipment << prompt.select(t('builder.fighter.select_starting_weapon_2')) do |q|
      q.choice t('object.martial_weapon_and_shield'), :martial_weapon_and_shield
      q.choice t('object.two_martial_weapons'), :two_martial_weapons
    end

    starting_equipment << prompt.select(t('builder.fighter.select_starting_weapon_3')) do |q|
      q.choice t('object.light_crossbow_and_20_bolts'), :light_crossbow_and_20_bolts
      q.choice t('object.two_handaxes'), :two_handaxes
    end

    # starting_equipment << prompt.select(t('builder.fighter.select_starting_weapon_4')) do |q|
    #   q.choice t('object.dungeoneers_pack'), :dungeoneers_pack
    #   q.choice t('object.explorers_pack'), :explorers_pack
    # end

    martial_weapons = session.load_weapons.map do |k, weapon|
      next unless weapon[:proficiency_type]&.include?('martial')
      next if weapon[:rarity] && weapon[:rarity] != 'common'

      k
    end.compact

    starting_equipment.each do |equipment|
      case equipment
      when :chain_mail
        @class_values[:equipped] << 'chain_mail'
      when :longbow_and_arrows
        @class_values[:inventory] << {
          type: 'longbow',
          qty: 1
        }
      when :martial_weapon_and_shield
        chosen_martial_weapon = prompt.select(t('builder.select_martial_weapon')) do |q|
          martial_weapons.each do |weapon|
            q.choice t("object.weapons.#{weapon}"), weapon
          end
        end
        @class_values[:inventory] << {
          type: chosen_martial_weapon,
          qty: 1
        }
        @class_values[:inventory] << {
          type: 'shield',
          qty: 1
        }
      when :two_martial_weapons
        chosen_martial_weapons = prompt.multi_select(t('builder.select_martial_weapon'), min: 2, max: 2) do |q|
          martial_weapons.each do |weapon|
            q.choice t("object.weapons.#{weapon}"), weapon
          end
        end
        chosen_martial_weapons.each do |w|
          @class_values[:inventory] << {
            type: w,
            qty: 1
          }
        end
      when :light_crossbow_and_20_bolts
        @class_values[:inventory] << {
          type: 'crossbow',
          qty: 1
        }
        @class_values[:inventory] << {
          type: 'bolts',
          qty: 20
        }
      when :two_handaxes
        @class_values[:inventory] << {
          type: 'handaxe',
          qty: 2
        }
        # when :dungeoneers_pack
        # when :explorers_pack
      end
    end

    result = Natural20::DieRoll.parse(@class_properties[:hit_die])
    @values[:max_hp] = result.die_count * result.die_type.to_i + modifier_table(@values.dig(:ability, :con))

    @class_values
  end
end