module Natural20::WizardBuilder
  def wizard_builder(build_values)
    @wizard_info = session.load_class('wizard')
    @class_values ||= {
      attributes: [],
      saving_throw_proficiencies: %w[intelligence wisdom],
      equipped: [],
      inventory: [{
        type: 'spellbook',
        qty: 1
      }],
      prepared_spells: [],
      spellbook: []
    }

    starting_equipment = []

    starting_equipment << prompt.select(t('builder.wizard.select_starting_weapon')) do |q|
      q.choice t('object.weapons.quarterstaff'), :quarterstaff
      q.choice t('object.weapons.dagger'), :dagger
    end

    starting_equipment << prompt.select(t('builder.wizard.select_starting_weapon_2')) do |q|
      q.choice t('object.component_pouch'), :component_pouch
      q.choice t('object.arcane_focus'), :arcane_focus
    end

    starting_equipment.each do |equip|
      case equip
      when :quarterstaff
        @class_values[:equipped] << 'quarterstaff'
      when :dagger
        @class_values[:equipped] << 'dagger'
      when :component_pouch
        @class_values[:inventory] << {
          type: 'component_pouch',
          qty: 1
        }
      when :arcane_focus
        arcane_focus = prompt.select(t('builder.wizard.select_arcane_focus')) do |q|
          %w[crytal orb rod staff wand].each do |equip|
            q.choice t(:"object.#{equip}"), equip
          end
        end
        @class_values[:inventory] << {
          type: arcane_focus,
          qty: 1
        }
      end
    end

    @class_values[:prepared_spells] = prompt.multi_select(t('builder.wizard.select_cantrip'), min: 3, max: 3) do |q|
      @wizard_info.dig(:spell_list, :cantrip).each do |cantrip|
        next unless session.load_spell(cantrip)

        q.choice t(:"spell.#{cantrip}"), cantrip
      end
    end

    @class_values[:spellbook] = prompt.multi_select(t('builder.wizard.select_spells'), min: 6, max: 6) do |q|
      @wizard_info.dig(:spell_list, :level_1).each do |spell|
        next unless session.load_spell(spell)

        q.choice t(:"spell.#{spell}"), spell
      end
    end

    prepared_spells_count = modifier_table(build_values[:ability][:int]) + 1

    @class_values[:prepared_spells] = prompt.multi_select(t('builder.wizard.select_prepared_spells'), min: prepared_spells_count, max: prepared_spells_count) do |q|
      @class_values[:spellbook].each do |spell|
        q.choice t(:"spell.#{spell}"), spell
      end
    end
    @class_values
  end
end
