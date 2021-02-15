require 'natural_20/cli/builder/fighter_builder'
require 'natural_20/cli/builder/rogue_builder'
require 'natural_20/cli/builder/wizard_builder'
module Natural20
  class CharacterBuilder
    include Natural20::FighterBuilder
    include Natural20::RogueBuilder
    include Natural20::WizardBuilder
    include Natural20::InventoryUI

    attr_reader :session, :battle

    def initialize(prompt, session, battle)
      @prompt = prompt
      @session = session
      @battle = battle
    end

    def build_character
      @values = {
        hit_die: 'inherit',
        classes: {},
        ability: {},
        skills: [],
        level: 1,
        token: ['X'],
        tools: []
      }
      loop do
        ability_method = :random

        @values[:name] = prompt.ask(t('builder.enter_name'), default: @values[:name]) do |q|
          q.required true
          q.modify :capitalize
        end

        @values[:pronoun] = prompt.select(t('builder.enter_name_pronoun')) do |q|
          q.choice t(:"builder.pronoun.he"), 'he/him/his'
          q.choice t(:"builder.pronoun.she"), 'she/her/hers'
          q.choice t(:"builder.pronoun.they"), 'they/them/their'
          q.choice t(:"builder.pronoun.ze"), 'ze/hir/hirs'
        end

        @values[:token] = [prompt.ask(t('builder.token'), default: @values[:name][0])]
        @values[:color] = prompt.select(t('builder.token_color')) do |q|
          %i[
            red light_red
            green light_green
            yellow light_yellow
            blue light_blue
            magenta light_magenta
            cyan light_cyan
            white light_white
          ].each do |color|
            q.choice @values[:token].first.colorize(color), color
          end
        end

        description = prompt.multiline(t('builder.description')) do |q|
          q.default t('builder.default_description')
        end

        @values[:description] = description.is_a?(Array) ? description.join("\n") : description

        races = session.load_races
        @values[:race] = prompt.select(t('builder.select_race')) do |q|
          races.each do |race, details|
            q.choice details[:label] || race.humanize, race
          end
        end

        race_detail = races[@values[:race]]
        if race_detail[:subrace]
          @values[:subrace] = prompt.select(t('builder.select_subrace')) do |q|
            race_detail[:subrace].each do |subrace, detail|
              q.choice detail[:label] || t("builder.races.#{subrace}"), subrace
            end
          end
        end
        subrace_detail = race_detail.dig(:subrace, @values[:subrace]&.to_sym)

        known_languages = race_detail.fetch(:languages, []) + (subrace_detail&.fetch(:languages, []) || [])
        language_choice = race_detail.fetch(:language_choice, 0) + (subrace_detail&.fetch(:language_choice, 0) || 0)
        if language_choice.positive?
          language_selector(ALL_LANGUAGES - known_languages, min: language_choice, max: language_choice)
        end

        race_bonus = race_detail[:attribute_bonus] || {}
        subrace_bonus = subrace_detail&.fetch(:attribute_bonus, {}) || {}

        attribute_bonuses = race_bonus.merge!(subrace_bonus)

        k = prompt.select(t('builder.class')) do |q|
          session.load_classes.each do |klass, details|
            q.choice details[:label] || klass.humanize, klass.to_sym
          end
        end

        @values[:classes][k.to_sym] = 1
        @class_properties = session.load_class(k)

        if race_detail[:tool_proficiencies_choice]
          num_tools_choices = race_detail[:tool_proficiencies_choice]
          @values[:tools] = prompt.multi_select(t('builder.select_tools_proficiency'), min: num_tools_choices, max: num_tools_choices) do |q|
            race_detail[:tool_proficiencies].each do |prof|
              q.choice t("builder.tools.#{prof}"), prof
            end
          end
        end

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
          @values[:ability][type.to_sym] = ability_scores[score_index] + bonus
        end

        class_skills_selector

        send(:"#{k}_builder", @values)

        @values.merge!(@class_values)
        @pc = Natural20::PlayerCharacter.new(session, @values)
        character_sheet(@pc)
        break if prompt.yes?(t('builder.review'))
      end

      session.save_character(@values[:name], @values)

      @pc
    end

    ALL_LANGUAGES = %w[abyssal
                       celestial
                       common
                       deep_speech
                       draconic
                       dwarvish
                       elvish
                       giant
                       gnomish
                       goblin
                       halfling
                       infernal
                       orc
                       primordial
                       sylvan
                       undercommon]

    protected

    def language_selector(languages = ALL_LANGUAGES, min: 1, max: 1)
      @values[:languages] = prompt.multi_select(t('builder.select_languages'), min: min, max: max, per_page: 20) do |q|
        languages.each do |lang|
          q.choice t("language.#{lang}"), lang
        end
      end
    end

    def class_skills_selector
      class_skills = @class_properties[:available_skills]
      num_choices = @class_properties[:available_skills_choices]
      @values[:skills] += prompt.multi_select(t("builder.#{@values[:classes].keys.first}.select_skill"),
                                              min: num_choices, max: num_choices, per_page: 20) do |q|
        class_skills.each do |skill|
          q.choice t("builder.skill.#{skill}"), skill
        end
      end
    end

    def modifier_table(value)
      mod_table = [[1, 1, -5],
                   [2, 3, -4],
                   [4, 5, -3],
                   [6, 7, -2],
                   [8, 9, -1],
                   [10, 11, 0],
                   [12, 13, 1],
                   [14, 15, 2],
                   [16, 17, 3],
                   [18, 19, 4],
                   [20, 21, 5],
                   [22, 23, 6],
                   [24, 25, 7],
                   [26, 27, 8],
                   [28, 29, 9],
                   [30, 30, 10]]

      mod_table.each do |row|
        low, high, mod = row
        return mod if value.between?(low, high)
      end
    end

    attr_reader :prompt
  end
end
