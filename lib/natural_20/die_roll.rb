# typed: true
module Natural20
  class DieRollDetail
    attr_writer :die_count, :die_type, :modifier, :modifier_op

    # @return [Integer]
    def die_count
      @die_count
    end

    # @return [String]
    def die_type
      @die_type
    end

    # @return [Integer]
    def modifier
      @modifier
    end

    # @return [Symbol]
    def modifier_op
      @modifier_op
    end
  end
  class DieRoll


    class DieRolls
      attr_accessor :rolls

      def initialize(rolls = [])
        @rolls = rolls
      end

      def add_to_front(die_roll)
        if die_roll.is_a?(Natural20::DieRoll)
          @rolls.unshift(die_roll)
        elsif die_roll.is_a?(DieRolls)
          @rolls = die_roll.rolls + @rolls
        end
      end

      def +(other)
        if other.is_a?(Natural20::DieRoll)
          @rolls << other
        elsif other.is_a?(DieRolls)
          @rolls += other.rolls
        end
      end

      def result
        @rolls.inject(0) do |sum, roll|
          sum + roll.result
        end
      end

      def ==(other)
        return false if other.rolls.size != @rolls.size

        @rolls.each_with_index do |roll, index|
          return false if other.rolls[index] != roll
        end

        true
      end

      def to_s
        @rolls.map(&:to_s).join(' + ')
      end
    end

    attr_reader :rolls, :modifier, :die_sides

    # This represents a dice roll
    # @param rolls [Array] Integer dice roll representations
    # @param modifier [Integer] a constant value to add to the roll
    def initialize(rolls, modifier, die_sides = 20, advantage: false, disadvantage: false, description: nil)
      @rolls = rolls
      @modifier = modifier
      @die_sides = die_sides
      @advantage = advantage
      @disadvantage = disadvantage
      @description = description
    end

    # This is a natural 20 or critical roll
    # @return [Boolean]
    def nat_20?
      if @advantage
        @rolls.map(&:max).detect { |r| r == 20 }
      elsif @disadvantage
        @rolls.map(&:min).detect { |r| r == 20 }
      else
        @rolls.include?(20)
      end
    end

    def nat_1?
      if @advantage
        @rolls.map(&:max).detect { |r| r == 1 }
      elsif @disadvantage
        @rolls.map(&:min).detect { |r| r == 1 }
      else
        @rolls.include?(1)
      end
    end

    # computes the integer result of the dice roll
    # @return [Integer]
    def result
      sum = if @advantage
              @rolls.map(&:max).sum
            elsif @disadvantage
              @rolls.map(&:min).sum
            else
              @rolls.sum
            end

      sum + @modifier
    end

    # adds color flair to the roll depending on value
    # @param roll [String,Integer]
    # @return [String]
    def color_roll(roll)
      case roll
      when 1
        roll.to_s.colorize(:red)
      when @die_sides
        roll.to_s.colorize(:green)
      else
        roll.to_s
      end
    end

    def to_s
      rolls = @rolls.map do |r|
        if @advantage
          r.map do |i|
            i == r.max ? color_roll(i).bold : i.to_s.colorize(:gray)
          end.join(' | ')
        elsif @disadvantage
          r.map do |i|
            i == r.min ? color_roll(i).bold : i.to_s.colorize(:gray)
          end.join(' | ')
        else
          color_roll(r)
        end
      end

      if @modifier != 0
        "(#{rolls.join(' + ')}) + #{@modifier}"
      else
        "(#{rolls.join(' + ')})"
      end
    end

    def self.numeric?(c)
      return true if c =~ /\A\d+\Z/

      begin
        true if Float(c)
      rescue StandardError
        false
      end
    end

    def ==(other)
      return true if other.rolls == @rolls && other.modifier == @modifier && other.die_sides == @die_sides

      false
    end

    def +(other)
      if other.is_a?(DieRolls)
        other.add_to_front(self)
        other
      else
        DieRolls.new([self, other])
      end
    end

    # @param die_roll_str [String]
    # @return [Natural20::DieRollDetail]
    def self.parse(roll_str)
      die_count_str = ''
      die_type_str = ''
      modifier_str = ''
      modifier_op = ''
      state = :initial

      roll_str.strip.each_char do |c|
        case state
        when :initial
          if numeric?(c)
            die_count_str << c
          elsif c == 'd'
            state = :die_type
          elsif c == '+'
            state = :modifier
          end
        when :die_type
          next if c == ' '

          if numeric?(c)
            die_type_str << c
          elsif c == '+'
            state = :modifier
          elsif c == '-'
            modifier_op = '-'
            state = :modifier
          end
        when :modifier
          next if c == ' '

          modifier_str << c if numeric?(c)
        end
      end

      if state == :initial
        modifier_str = die_count_str
        die_count_str = '0'
      end

      number_of_die = die_count_str.blank? ? 1 : die_count_str.to_i

      detail = Natural20::DieRollDetail.new
      detail.die_count = number_of_die
      detail.die_type = die_type_str
      detail.modifier = modifier_str
      detail.modifier_op = modifier_op
      detail
    end

    # Rolls the dice, details on dice rolls and its values are preserved
    # @param roll_str [String] A dice roll expression
    # @param entity [Natural20::Entity]
    # @param crit [Boolean] A critial hit damage roll - double dice rolls
    # @param advantage [Boolean] Roll with advantage, roll twice and select the highest
    # @param disadvantage [Boolean] Roll with disadvantage, roll twice and select the lowest
    # @param battle [Natural20::Battle]
    # @return [Natural20::DieRoll]
    def self.roll(roll_str, crit: false, disadvantage: false, advantage: false, description: nil, entity: nil, battle: nil)

      die_sides = 20

      detail = parse(roll_str)
      number_of_die = detail.die_count
      die_type_str = detail.die_type
      modifier_str = detail.modifier
      modifier_op = detail.modifier_op

      return Natural20::DieRoll.new([number_of_die], "#{modifier_op}#{modifier_str}".to_i, 0) if die_type_str.blank?

      die_sides = die_type_str.to_i

      number_of_die *= 2 if crit
      description = t('dice_roll.description', description: description, roll_str: roll_str)
      rolls = if advantage || disadvantage
                if battle
                  battle.roll_for(entity, die_sides, number_of_die, description, advantage: advantage,
                                                                                 disadvantage: disadvantage)
                else
                  number_of_die.times.map { [(1..die_sides).to_a.sample, (1..die_sides).to_a.sample] }
                end
              elsif battle
                battle.roll_for(entity, die_sides, number_of_die, description)
              else
                number_of_die.times.map { (1..die_sides).to_a.sample }
              end
      Natural20::DieRoll.new(rolls, modifier_str.blank? ? 0 : "#{modifier_op}#{modifier_str}".to_i, die_sides,
                             advantage: advantage, disadvantage: disadvantage)
    end

    def self.t(key, options = {})
      I18n.t(key, options)
    end
  end
end
