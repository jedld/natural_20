class EventManager
  def self.clear
    @event_listeners = {}
  end

  def self.register_event_listener(events, callable)
    @event_listeners ||= {}
    events.each do |event|
      @event_listeners[event] ||= []
      @event_listeners[event] << callable unless @event_listeners[event].include?(callable)
    end
  end

  def self.received_event(event)
    return if @event_listeners.nil?

    @event_listeners[event[:event]]&.each do |callable|
      callable.call(event)
    end
  end

  def self.standard_cli
    EventManager.clear
    EventManager.register_event_listener([:died], ->(event) { puts "#{event[:source].name&.colorize(:blue)} died." })
    EventManager.register_event_listener([:unconsious], ->(event) { puts "#{event[:source].name&.colorize(:blue)} unconsious." })
    EventManager.register_event_listener([:attacked], lambda { |event|
      sneak = event[:sneak_attack] ? (event[:sneak_attack]).to_s : nil
      damage = (event[:damage_roll]).to_s
      damage_str = "#{[damage, sneak].compact.join(' + sneak ')} = #{event[:value]} #{event[:damage_type]}"
      puts "#{event[:as_reaction] ? 'Opportunity Attack: ' : ''} #{event[:source].name&.colorize(:blue)} attacked #{event[:target].name} with #{event[:attack_name]} to Hit: #{event[:attack_roll].to_s.colorize(:green)} for #{damage_str} damage."
    })
    EventManager.register_event_listener([:damage], ->(event) { puts "#{event[:source].name} #{event[:source].describe_health}" })
    EventManager.register_event_listener([:miss], ->(event) { puts "#{event[:as_reaction] ? 'Opportunity Attack: ' : ''} rolled #{event[:attack_roll]} ... #{event[:source].name&.colorize(:blue)} missed his attack #{event[:attack_name].colorize(:red)} on #{event[:target].name.colorize(:green)}" })
    EventManager.register_event_listener([:initiative], ->(event) { puts "#{event[:source].name&.colorize(:blue)} rolled a #{event[:roll]} = (#{event[:value]}) with dex tie break for initiative." })
    EventManager.register_event_listener([:move], ->(event) { puts "#{event[:source].name&.colorize(:blue)} moved #{(event[:path].size - 1) * 5}ft." })
    EventManager.register_event_listener([:dodge], ->(event) { puts "#{event[:source].name&.colorize(:blue)} takes the dodge action." })
    EventManager.register_event_listener([:help], ->(event) { puts "#{event[:source].name&.colorize(:blue)} is helping to attack #{event[:target].name&.colorize(:red)}" })
    EventManager.register_event_listener([:second_wind], ->(event) { puts SecondWindAction.describe(event) })
    EventManager.register_event_listener([:heal], ->(event) { puts "#{event[:source].name&.colorize(:blue)} heals for #{event[:value]}hp" })
    EventManager.register_event_listener([:object_interaction], lambda { |event|
                                                                  if event[:roll]
                                                                    puts "#{event[:roll]} = #{event[:roll].result} -> #{event[:reason]}"
                                                                  else
                                                                    puts (event[:reason]).to_s
                                                                  end
                                                                })
  end
end
