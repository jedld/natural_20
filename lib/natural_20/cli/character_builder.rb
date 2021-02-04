module Natural20::CharacterBuilder
  def build_character
    values = {
      hit_die: 'inherit',
      classes: {},
      ability: {}
    }
    loop do
      ability_method = :random

      values[:name] = prompt.ask(t('builder.enter_name', default: values[:name])) do |q|
        q.required true
        q.validate(/\A\w+\Z/)
        q.modify :capitalize
      end
      races = session.load_races
      values[:race] = prompt.select(t('builder.select_race', default: values[:race])) do |q|
        races.each do |race, details|
          q.choice details[:label] || race.humanize, race
        end
      end

      race_detail = races[values[:race]]
      values[:subrace] = prompt.select(t('builder.select_subrace', default: values[:subrace])) do |q|
        race_detail[:subrace].each do |subrace, detail|
          q.choice detail[:label] || t("builder.races.#{subrace}"), subrace
        end
      end

      race_bonus = race_detail[:attribute_bonus] || {}
      subrace_bonus = race_detail.dig(:attribute_bonus, :subrace, values[:subrace], :attribute_bonus) || {}

      attribute_bonuses = race_bonus.merge!(subrace_bonus)

      k = prompt.select('builder.class', default: values[:classes].keys.first) do |q|
        session.load_classes.each do |klass, details|
          q.choice details[:label] || klass.humanize, klass
        end
      end
      values[:classes][k] = 1
      class_properties = session.load_class(k)
      result = Natural20::DieRoll.parse(class_properties[:hit_die])
      values[:max_hp] = result.die_count * result.die_type.to_i

      ability_method = prompt.select(t('builder.ability_score_method')) do |q|
        q.choice t('builder.ability_score.random'), :random
        q.choice t('builder.ability_score.fixed'), :fixed
        # q.choice t('builder.ability_score.point_buy'), :point_buy
      end

      ability_scores = if ability_method == :random
                         6.times.map do |index|
                           r = 4.times.map do |_x|
                             die_roll = Natural20::DieRoll.roll('1d6', battle: battle,
                                                                       description: t('dice_roll.ability_score', roll_num: index + 1))
                             die_roll.result
                           end.sort.reverse
                           puts "#{index + 1}. #{r.join(',')}"

                           r.take(3).sum
                         end.sort.reverse
                       elsif ability_method == :fixed
                         [15, 14, 13, 12, 10, 8]
                       end

      puts t('builder.assign_ability_scores', scores: ability_scores.join(','))

      chosen_score = []

      Natural20::Entity::ATTRIBUTE_TYPES_ABBV.each do |type|
        bonus = attribute_bonuses[type.to_sym] || 0
        ability_choice_str = t("builder.#{type}")
        ability_choice_str += " (+#{bonus})" if bonus.positive?
        score_index = prompt.select(ability_choice_str) do |q|
          ability_scores.each_with_index do |score, index|
            next if chosen_score.include?(index)

            q.choice score, index
          end
        end

        chosen_score << score_index
        values[:ability][type.to_sym] = ability_scores[score_index] + bonus
      end

      class_features = fighter_build if k == 'fighter'
      values.merge!(class_features)
      pc = Natural20::PlayerCharacter.new(session, values)
      character_sheet(pc)
      break if prompt.yes?(t('builder.review'))
    end
    session.save_character(values[:name], values)
  end

  def fighter_build
    @class_values ||= {
      attributes: [],
      saving_throw_proficiencies: %w[strength constitution],
      skills: [],
      equipped: [],
      inventory: []
    }

    fighter_skills = %w[acrobatics animal_handling athletics history insight intimidation perception survival]
    @class_values[:skills] = prompt.multi_select(t('builder.fighter.select_skill'), min: 2, max: 2, default: @class_values[:skills]) do |q|
      fighter_skills.each do |skill|
        q.choice t("builder.skill.#{skill}"), skill
      end
    end

    fighter_features = %w[archery defense dueling great_weapon_fighting protection two_weapon_fighting]
    @class_values[:attributes] << prompt.select(t('builder.fighter.select_fighting_style')) do |q|
      fighter_features.each do |style|
        q.choice t("builder.fighter.#{style}"), style
      end
    end

    starting_equipment = []
    starting_equipment << prompt.select(t('builder.fighter.select_starting_weapon')) do |q|
      q.choice t('object.chain_mail'), :chain_mail
      q.choice t('object.longbow_and_arros'), :longbow_and_arrows
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
      next unless weapon[:proficiency_type].include?('martial')

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
    @class_values
  end
end
