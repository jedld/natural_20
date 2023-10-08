# Helper module for utilities in computing attacks
module Natural20::AttackHelper
  # Handles after attack event hooks
  # @param battle [Natural20::Battle]
  # @param target [Natural20::Entity]
  # @param source [Natural20::Entity]
  def after_attack_roll_hook(battle, target, source, attack_roll, effective_ac, opts = {})
    force_miss = false

    # check prepared spells of target for a possible reaction
    events = target.prepared_spells.map do |spell|
      spell_details = battle.session.load_spell(spell)
      _qty, resource = spell_details[:casting_time].split(':')
      next unless target.has_reaction?(battle)
      next unless resource == 'reaction'

      spell_class = spell_details[:spell_class].constantize
      next unless spell_class.respond_to?(:after_attack_roll)

      result, force_miss_result = spell_class.after_attack_roll(battle, target, source, attack_roll,
                                                                effective_ac, opts)
      force_miss = true if force_miss_result == :force_miss
      result
    end.flatten.compact

    events.each do |item|
      Natural20::Action.descendants.each do |klass|
        klass.apply!(battle, item)
      end
    end

    force_miss
  end

  def effective_ac(battle, target)
    cover_ac_adjustments = 0
    ac = if battle && battle.map
           cover_ac_adjustments = calculate_cover_ac(battle.map, target)
           target.armor_class + cover_ac_adjustments # calculate AC with cover
         else
           target.armor_class
         end
    [ac, cover_ac_adjustments]
  end

  # Computes cover armor class adjustment
  # @param map [Natural20::BattleMap]
  # @param target [Natural20::Entity]
  # @return [Integer]
  def calculate_cover_ac(map, target)
    cover_calculation(map, @source, target)
  end
end
