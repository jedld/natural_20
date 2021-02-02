module Natural20::CharacterBuilder
  def build_character
    values = {
      hit_die: 'inherit',
      classes: {},
      ability: {}
    }

    ability_method = :random

    values[:name] = prompt.ask(t('builder.enter_name', default: values[:name])) do |q|
      q.required true
      q.validate(/\A\w+\Z/)
      q.modify :capitalize
    end

    values[:race] = prompt.select(t('builder.select_race', default: values[:race])) do |q|
      session.load_races.each do |race, details|
        q.choice details[:label] || race.humanize, race
      end
    end

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
      q.choice t('builder.fixed'), :fixed
      q.choice t('builder.ability_score.point_buy'), :point_buy
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
      score_index = prompt.select(t("builder.#{type}")) do |q|
        ability_scores.each_with_index do |score, index|
          next if chosen_score.include?(index)

          q.choice score, index
        end
      end

      chosen_score << score_index
      values[:ability][type.to_sym] = ability_scores[score_index]
    end
    session.save_character(values[:name], values)
  end
end
