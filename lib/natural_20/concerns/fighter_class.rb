require "lib/concerns/fighter_actions/second_wind_action"
module FighterClass
  attr_accessor :fighter_level, :second_wind_count

  def initialize_fighter
    @second_wind_count = 1
  end

  def second_wind_die
    "1d10+#{@fighter_level}"
  end

  def second_wind!(amt)
    @second_wind_count -= 1
    heal!(amt)
  end

  def special_actions_for_fighter(session, battle)
    %i[second_wind].map do |type|
      next unless "#{type.to_s.camelize}Action".constantize.can?(self, battle)

      case type
      when :second_wind
        SecondWindAction.new(session, self, :second_wind)
      end
    end.compact
  end
end