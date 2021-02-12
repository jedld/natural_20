module Natural20::RogueBuilder
  def rogue_builder(_build_values)
    @class_values ||= {
      attributes: [],
      saving_throw_proficiencies: %w[dexterity intelligence],
      equipped: %w[leather dagger dagger],
      inventory: [],
      tools: ['thieves_tools'],
      expertise: []
    }

    @class_values[:expertise] = prompt.multi_select(t('builder.rogue.expertise'), min: 2, max: 2) do |q|
      @values[:skills].each do |skill|
        q.choice t("builder.skill.#{skill}"), skill
      end
      q.choice t('builder.skill.thieves_tools'), 'thieves_tools'
    end

    starting_equipment = []
    starting_equipment << prompt.select(t('builder.rogue.select_starting_weapon')) do |q|
      q.choice t('object.rapier'), :rapier
      q.choice t('object.shortsword'), :shortsword
    end

    starting_equipment << prompt.select(t('builder.rogue.select_starting_weapon_2')) do |q|
      q.choice t('object.shortbow_and_quiver'), :shortbow_and_quiver
      q.choice t('object.shortsword'), :shortsword
    end

    starting_equipment.each do |equip|
      case equip
      when :rapier
        @class_values[:inventory] << {
          qty: 1,
          type: 'rapier'
        }
      when :shortbow_and_quiver
        @class_values[:inventory] += [{
          type: 'shortbow',
          qty: 1
        },
                                      {
                                        type: 'arrows',
                                        qty: 20
                                      }]
      end
    end

    shortswords = starting_equipment.select { |a| a == :shortword }.size
    if shortswords > 0
      @class_values[:inventory] << {
        type: 'shortsword',
        qty: shortswords
      }
    end

    result = Natural20::DieRoll.parse(@class_properties[:hit_die])
    @values[:max_hp] = result.die_count * result.die_type.to_i + modifier_table(@values.dig(:ability, :con))

    @class_values
  end
end
