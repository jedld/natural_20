# typed: true
module Natural20
  class EventManager
    class EventLogger
      # @param log_level [Integer,String]
      def initialize(log_level)
        @log_level = log_level.to_i
      end

      def debug(message = '')
        puts message if @log_level < 1
      end
    end

    def self.clear
      @event_listeners = {}
    end

    # Registers an event listener
    # @param events [Symbol,Array<Symbol>] list of event types
    # @param callable [Proc] handler
    def self.register_event_listener(events, callable)
      events = [events] unless events.is_a?(Array)
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

    # Sets the current player so that event text can be customized
    # @param battle [Natural20::Battle] Current battle
    # @param entites [Array] An array of entities
    def self.set_context(battle, entities = [])
      @battle = battle
      @current_entity_context = entities
    end

    #  @return [EventLogger]
    def self.logger
      @logger ||= EventLogger.new(ENV['NAT20_LOG_LEVEL'].presence || '1')
      @logger
    end

    def self.standard_cli
      Natural20::EventManager.clear
      event_handlers = { died: lambda { |event|
                                 puts "#{show_name(event)} died."
                               },
                         unconscious: lambda { |event|
                                        puts "#{show_name(event)} unconscious."
                                      },
                         attacked: lambda { |event|
                                     sneak = event[:sneak_attack] ? (event[:sneak_attack]).to_s : nil
                                     damage = (event[:damage_roll]).to_s
                                     damage_str = "#{[damage,
                                                      sneak].compact.join(' + sneak ')} = #{event[:value]} #{event[:damage_type]}"
                                     if event[:cover_ac].try(:positive?)
                                       cover_str = " (behind cover +#{event[:cover_ac]} ac)"
                                     end
                                     puts "#{event[:as_reaction] ? 'Opportunity Attack: ' : ''}#{show_name(event)} attacked #{event[:target].name}#{cover_str} with #{event[:attack_name]} to Hit: #{event[:attack_roll].to_s.colorize(:green)} for #{damage_str} damage."
                                   },
                         damage: lambda { |event|
                                   puts "#{show_name(event)} #{event[:source].describe_health}"
                                 },
                         miss: lambda { |event|
                                 puts "#{event[:as_reaction] ? 'Opportunity Attack: ' : ''} rolled #{event[:attack_roll]} ... #{event[:source].name&.colorize(:blue)} missed his attack #{event[:attack_name].colorize(:red)} on #{event[:target].name.colorize(:green)}"
                               },
                         initiative: lambda { |event|
                                       puts "#{show_name(event)} rolled a #{event[:roll]} = (#{event[:value]}) with dex tie break for initiative."
                                     },
                         move: lambda { |event|
                                 puts "#{show_name(event)} moved #{(event[:path].size - 1) * event[:feet_per_grid]}ft."
                               },
                         dodge: lambda { |event|
                                  puts t('event.dodge', name: show_name(event))
                                },
                         help: lambda { |event|
                                 puts "#{show_name(event)} is helping to attack #{event[:target].name&.colorize(:red)}"
                               },
                         second_wind: lambda { |event|
                                        puts SecondWindAction.describe(event)
                                      },
                         heal: lambda { |event|
                                 puts "#{show_name(event)} heals for #{event[:value]}hp"
                               },
                         hit_die: lambda { |event|
                           puts t('event.hit_die', source: show_name(event), roll: event[:roll].to_s,
                                                   value: event[:roll].result)
                         },
                         object_interaction: lambda { |event|
                                               if event[:roll]
                                                 puts "#{event[:roll]} = #{event[:roll].result} -> #{event[:reason]}"
                                               else
                                                 puts (event[:reason]).to_s
                                               end
                                             },
                         perception: lambda { |event|
                                       puts "#{show_name(event)} rolls #{event[:perception_roll]} on perception"
                                     },

                         death_save: lambda { |event|
                                       puts t('event.death_save', name: show_name(event), roll: event[:roll].to_s, value: event[:roll].result,
                                                                  saves: event[:saves], fails: event[:fails]).colorize(:blue)
                                     },

                         death_fail: lambda { |event|
                                       if event[:roll]
                                         puts t('event.death_fail', name: show_name(event), roll: event[:roll].to_s, value: event[:roll].result,
                                                                    saves: event[:saves], fails: event[:fails]).colorize(:red)
                                       else
                                         puts t('event.death_fail_hit', name: show_name(event), saves: event[:saves],
                                                                        fails: event[:fails]).colorize(:red)
                                       end
                                     },

                         prone: lambda { |event|
                                  puts t('event.status.prone', name: show_name(event))
                                },

                         stand: lambda { |event|
                                  puts t('event.status.stand', name: show_name(event))
                                },

                         %i[acrobatics athletics] => lambda { |event|
                                                       if event[:success]
                                                         puts t("event.#{event[:event]}.success", name: show_name(event), roll: event[:roll],
                                                                                                  value: event[:roll].result)
                                                       else
                                                         puts t("event.#{event[:event]}.failure", name: show_name(event), roll: event[:roll],
                                                                                                  value: event[:roll].result)
                                                       end
                                                     },

                         start_of_combat: lambda { |event|
                           puts t('event.combat_start')
                           event[:combat_order].each_with_index do |entity_and_initiative, index|
                             entity, initiative = entity_and_initiative
                             puts "#{index + 1}. #{decorate_name(entity)} #{initiative}"
                           end
                         },

                         end_of_combat: lambda { |_event|
                                          puts t('event.combat_end')
                                        },
                         grapple_success: lambda { |event|
                           if event[:target_roll]
                             puts t('event.grapple_success',
                                    source: show_name(event), target: event[:target]&.name,
                                    source_roll: event[:source_roll],
                                    source_roll_value: event[:source_roll].result,
                                    target_roll: event[:target_roll],
                                    target_roll_value: event[:target_roll].result)
                           else
                             puts t('event.grapple_success_no_roll',
                                    source: show_name(event), target: event[:target]&.name)
                           end
                         },
                         first_aid: lambda { |event|
                           puts t('event.first_aid', name: show_name(event),
                                                     target: event[:target]&.name, roll: event[:roll], value: event[:roll].result)
                         },
                         first_aid_failure: lambda { |event|
                                              puts t('event.first_aid_failure', name: show_name(event),
                                                                                target: event[:target]&.name, roll: event[:roll], value: event[:roll].result)
                                            },
                         grapple_failure: lambda { |event|
                           puts t('event.grapple_failure',
                                  source: show_name(event), target: event[:target]&.name,
                                  source_roll: event[:source_roll],
                                  source_roll_value: event[:source_roll].result,
                                  target_roll: event[:target_roll],
                                  target_roll_value: event[:target_roll_value].result)
                         },
                         drop_grapple: lambda { |event|
                                         puts t('event.drop_grapple',
                                                source: show_name(event), target: event[:target]&.name)
                                       },
                         %i[escape_grapple_success escape_grapple_failure] => lambda { |event|
                                                                                puts t("event.#{event[:event]}",
                                                                                       source: show_name(event), target: event[:target]&.name,
                                                                                       source_roll: event[:source_roll],
                                                                                       source_roll_value: event[:source_roll].result,
                                                                                       target_roll: event[:target_roll],
                                                                                       target_roll_value: event[:target_roll].result)
                                                                              } }
      event_handlers.each do |k, v|
        EventManager.register_event_listener(k, v)
      end
    end

    # @param event [Hash]
    def self.show_name(event)
      decorate_name(event[:source])
    end

    # @param event [Hash]
    def self.decorate_name(entity)
      if @battle && @current_entity_context && entity

        seen_attacker = @current_entity_context.detect do |c|
          c == entity || @battle.map.can_see?(c, entity)
        end
        color = @battle.entity_group_for(seen_attacker) != @battle.entity_group_for(entity) ? :red : :blue
        seen_attacker ? entity.name&.colorize(color) : I18n.t('event.something')
      else
        entity.name&.colorize(:blue)
      end
    end

    def self.t(token, options = {})
      I18n.t(token, options)
    end
  end
end
