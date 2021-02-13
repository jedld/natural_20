class SpellAction < Natural20::Action
  extend Natural20::ActionDamage

  attr_accessor :target, :spell_action, :spell, :other_params, :at_level

  def self.can?(entity, battle, options = {})
    return false unless entity.has_spells?

    battle.nil? || !battle.ongoing? || can_cast?(entity, battle, options[:spell])
  end

  # @param battle [Natural20::Battle]
  # @param spell [Symbol]
  def self.can_cast?(entity, battle, spell)
    return true unless spell

    spell_details = battle.session.load_spell(spell)
    amt, resource = spell_details[:casting_time].split(':')

    return true if resource == ('action') && battle.total_actions(entity).positive?

    false
  end

  def self.build(session, source)
    action = SpellAction.new(session, source, :spell)
    action.build_map
  end

  def build_map
    OpenStruct.new({
                     action: self,
                     param: [
                       {
                         type: :select_spell
                       }
                     ],
                     next: lambda { |spell_choice|
                             spell, at_level = spell_choice
                             @spell = session.load_spell(spell)
                             raise "spell not found #{spell}" unless @spell

                             self.at_level = at_level
                             spell_class = @spell[:spell_class].blank? ? "Natural20::#{spell.to_s.classify}Spell" : @spell[:spell_class]
                             @spell_action = spell_class.constantize.new(@source, spell, @spell)
                             @spell_action.action = self
                             @spell_action.build_map(self)
                           }
                   })
  end

  def resolve(_session, _map = nil, opts = {})
    battle = opts[:battle]
    @result = spell_action.resolve(@source, battle, self)
    self
  end

  def self.apply!(battle, item)
    Natural20::Spell.descendants.each do |klass|
      klass.apply!(battle, item)
    end
    case item[:type]
    when :spell_damage
      damage_event(item, battle)
      consume_resource(battle, item)
    when :spell_miss
      consume_resource(battle, item)
      Natural20::EventManager.received_event({ attack_roll: item[:attack_roll],
                                               attack_name: item[:attack_name],
                                               advantage_mod: item[:advantage_mod],
                                               as_reaction: !!item[:as_reaction],
                                               adv_info: item[:adv_info],
                                               source: item[:source], target: item[:target], event: :miss })
    end
  end

  # @param battle [Natural20::Battle]
  # @param item [Hash]
  def self.consume_resource(battle, item)
    amt, resource = item.dig(:spell, :casting_time).split(':')
    spell_level = item.dig(:spell, :level)
    case resource
    when 'action'
      battle.consume(item[:source], :action)
    when 'reaction'
      battle.consume(item[:source], :reaction)
    end

    item[:source].consume_spell_slot!(spell_level) if spell_level.positive?
  end
end
