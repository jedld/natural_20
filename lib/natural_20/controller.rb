module Natural20
  class Controller
    def roll_for(entity, die_type, number_of_times, description, advantage: false, disadvantage: false); end

    # Return moves by a player using the commandline UI
    # @param entity [Natural20::Entity] The entity to compute moves for
    # @param battle [Natural20::Battle] An instance of the current battle
    # @return [Array(Natural20::Action)]
    def move_for(entity, battle); end
  end
end
