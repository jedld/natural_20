require 'natural_20/cli/inventory_ui'
require 'natural_20/cli/character_builder'

class CommandlineUI < Natural20::Controller
  include Natural20::InventoryUI
  include Natural20::MovementHelper
  include Natural20::Cover

  TTY_PROMPT_PER_PAGE = 20
  attr_reader :battle, :map, :session, :test_mode

  # Creates an instance of a commandline UI helper
  # @param battle [Natural20::Battle]
  # @param map [Natural20::BattleMap]
  def initialize(battle, map, test_mode: false)
    @battle = battle
    @session = battle.session
    @map = map
    @test_mode = test_mode
    @renderer = Natural20::MapRenderer.new(@map, @battle)
  end

  def target_name(entity, target, weapon: nil)
    cover_ac = cover_calculation(@map, entity, target)
    target_labels = []
    target_labels << target.name.colorize(:red)
    target_labels << "(cover AC +#{cover_ac})" if cover_ac.positive?
    if weapon
      advantage_mod = target_advantage_condition(battle, entity, target, weapon)
      adv_details, disadv_details = compute_advantages_and_disadvantages(battle, entity, target, weapon)
      target_labels << t(:with_advantage) if advantage_mod.positive?
      target_labels << t(:with_disadvantage) if advantage_mod.negative?

      reasons = []
      adv_details.each do |d|
        reasons << "+#{t("attack_status.#{d}")}".colorize(:blue)
      end
      disadv_details.each do |d|
        reasons << "-#{t("attack_status.#{d}")}".colorize(:red)
      end

      target_labels << reasons.join(',')
    end
    target_labels.join(' ')
  end

  # Create a attack target selection CLI UI
  # @param entity [Natural20::Entity]
  # @param action [Natural20::Action]
  # @option options range [Integer]
  # @options options target [Array<Natural20::Entity>] passed when there are specific valid targets
  def attack_ui(entity, action, options = {})
    weapon_details = options[:weapon] ? session.load_weapon(options[:weapon]) : nil
    selected_targets = []
    valid_targets = options[:targets] || battle.valid_targets_for(entity, action, target_types: options[:target_types],
                                                                                  range: options[:range], filter: options[:filter])
    target = prompt.select("#{entity.name} targets") do |menu|
      valid_targets.each do |target|
        menu.choice target_name(entity, target, weapon: weapon_details), target
      end
      menu.choice 'Manual - Use cursor to select a target instead', :manual
      menu.choice 'Back', nil
    end

    return nil if target == 'Back'

    if target == :manual
      valid_targets = options[:targets] || battle.valid_targets_for(entity, action,
                                                                    target_types: options[:target_types], range: options[:range],
                                                                    filter: options[:filter],
                                                                    include_objects: true)
      targets = target_ui(entity, weapon: weapon_details, validation: lambda { |selected|
                                                                        selected_entities = map.thing_at(*selected)

                                                                        return false if selected_entities.empty?

                                                                        selected_entities.detect do |selected_entity|
                                                                          valid_targets.include?(selected_entity)
                                                                        end
                                                                      })
      targets = targets.flatten.select { |t| t.hp && t.hp.positive? }.flatten.uniq
      expected_targets = options.fetch(:num_select, 1)
      if targets.size > expected_targets
        loop do
          target = prompt.select('multiple targets at location(s) please select specific targets') do |menu|
            targets.flatten.uniq.each do |t|
              menu.choice t.name.to_s, t
            end
          end
          selected_targets << target
          break unless selected_targets.size < expected_targets
        end
      else
        selected_targets = targets
      end

      return nil if target.nil?
    else
      selected_targets << target
    end

    selected_targets.flatten
  end

  def self.clear_screen
    puts "\e[H\e[2J"
  end

  # @param entity [Natural20::Entity]
  def target_ui(entity, initial_pos: nil, num_select: 1, validation: nil, perception: 10, weapon: nil, look_mode: false)
    selected = []
    initial_pos ||= map.position_of(entity)
    new_pos = nil
    loop do
      CommandlineUI.clear_screen
      highlights = map.highlight(entity, perception)
      prompt.say(t('perception.looking_around', perception: perception))
      describe_map(battle.map, line_of_sight: entity)
      puts @renderer.render(line_of_sight: entity, select_pos: initial_pos, highlight: highlights)
      puts "\n"
      things = map.thing_at(*initial_pos)

      prompt.say(t('object.ground')) if things.empty?

      if map.can_see_square?(entity, *initial_pos)
        prompt.say(t('perception.using_darkvision')) unless map.can_see_square?(entity, *initial_pos,
                                                                                allow_dark_vision: false)
        things.each do |thing|
          prompt.say(target_name(entity, thing, weapon: weapon)) if thing.npc?

          prompt.say("#{thing.label}:")

          if !@battle.can_see?(thing, entity) && thing.sentient? && thing.conscious?
            prompt.say(t('perception.hide_success', label: thing.label))
          end

          map.perception_on(thing, entity, perception).each do |note|
            prompt.say("  #{note}")
          end
          health_description = thing.try(:describe_health)
          prompt.say("  #{health_description}") unless health_description.blank?
        end

        map.perception_on_area(*initial_pos, entity, perception).each do |note|
          prompt.say(note)
        end

        prompt.say(t('perception.terrain_and_surroundings'))
        terrain_adjectives = []
        terrain_adjectives << 'difficult terrain' if map.difficult_terrain?(entity, *initial_pos)

        intensity = map.light_at(initial_pos[0], initial_pos[1])
        terrain_adjectives << if intensity >= 1.0
                                'bright'
                              elsif intensity >= 0.5
                                'dim'
                              else
                                'dark'
                              end

        prompt.say("  #{terrain_adjectives.join(', ')}")
      else
        prompt.say(t('perception.dark'))
      end

      movement = prompt.keypress(look_mode ? t('perception.navigation_look') : t('perception.navigation'))

      if movement == 'w'
        new_pos = [initial_pos[0], initial_pos[1] - 1]
      elsif movement == 'a'
        new_pos = [initial_pos[0] - 1, initial_pos[1]]
      elsif movement == 'd'
        new_pos = [initial_pos[0] + 1, initial_pos[1]]
      elsif movement == 's'
        new_pos = [initial_pos[0], initial_pos[1] + 1]
      elsif ['x', ' '].include? movement
        next if validation && !validation.call(new_pos)

        selected << initial_pos
      elsif movement == 'r'
        new_pos = map.position_of(entity)
        next
      elsif movement == "\e"
        return []
      else
        next
      end

      next if new_pos.nil?
      next if new_pos[0].negative? || new_pos[0] >= map.size[0] || new_pos[1].negative? || new_pos[1] >= map.size[1]
      next unless map.line_of_sight_for?(entity, *new_pos)

      initial_pos = new_pos

      break unless movement != 'x'
    end

    selected.compact.map { |e| map.thing_at(*e) }
  end

  # @param entity [Natural20::Entity]
  def move_ui(entity, _options = {})
    path = [map.position_of(entity)]
    toggle_jump = false
    jump_index = []
    test_jump = []
    loop do
      puts "\e[H\e[2J"
      movement = map.movement_cost(entity, path, battle, jump_index)
      movement_cost = "#{(movement.cost * map.feet_per_grid).to_s.colorize(:green)}ft."
      if entity.prone?
        puts "movement (crawling) #{movement_cost}"
      elsif toggle_jump && !jump_index.include?(path.size - 1)
        puts "movement (ready to jump) #{movement_cost}"
      elsif toggle_jump
        puts "movement (jump) #{movement_cost}"
      else
        puts "movement #{movement_cost}"
      end
      describe_map(battle.map, line_of_sight: entity)
      puts @renderer.render(entity: entity, line_of_sight: entity, path: path, update_on_drop: true,
                            acrobatics_checks: movement.acrobatics_check_locations, athletics_checks: movement.athletics_check_locations)
      prompt.say('(warning) token cannot end its movement in this square') unless @map.placeable?(entity, *path.last,
                                                                                                  battle)
      prompt.say('(warning) need to perform a jump over this terrain') if @map.jump_required?(entity, *path.last)
      directions = []
      directions << '(wsadx) - movement, (qezc) diagonals'
      directions << 'j - toggle jump' unless entity.prone?
      directions << 'space/enter - confirm path'
      directions << 'r - reset'
      movement = prompt.keypress(directions.join(','))

      if movement == 'w'
        new_path = [path.last[0], path.last[1] - 1]
      elsif movement == 'a'
        new_path = [path.last[0] - 1, path.last[1]]
      elsif movement == 'd'
        new_path = [path.last[0] + 1, path.last[1]]
      elsif %w[s x].include?(movement)
        new_path = [path.last[0], path.last[1] + 1]
      elsif [' ', '\r'].include?(movement)
        next unless valid_move_path?(entity, path, battle, @map, manual_jump: jump_index)

        return [path, jump_index]
      elsif movement == 'q'
        new_path = [path.last[0] - 1, path.last[1] - 1]
      elsif movement == 'e'
        new_path = [path.last[0] + 1, path.last[1] - 1]
      elsif movement == 'z'
        new_path = [path.last[0] - 1, path.last[1] + 1]
      elsif movement == 'c'
        new_path = [path.last[0] + 1, path.last[1] + 1]
      elsif movement == 'r'
        path = [map.position_of(entity)]
        jump_index = []
        toggle_jump = false
        next
      elsif movement == 'j' && !entity.prone?
        toggle_jump = !toggle_jump
        next
      elsif movement == "\e"
        return nil
      else
        next
      end

      next if new_path[0].negative? || new_path[0] >= map.size[0] || new_path[1].negative? || new_path[1] >= map.size[1]

      test_jump = jump_index + [path.size] if toggle_jump

      if path.size > 1 && new_path == path[path.size - 2]
        jump_index.delete(path.size - 1)
        path.pop
        toggle_jump = if jump_index.include?(path.size - 1)
                        true
                      else
                        false
                      end
      elsif valid_move_path?(entity, path + [new_path], battle, @map, test_placement: false, manual_jump: test_jump)
        path << new_path
        jump_index = test_jump
      elsif valid_move_path?(entity, path + [new_path], battle, @map, test_placement: false, manual_jump: jump_index)
        path << new_path
        toggle_jump = false
      end
    end
  end

  def roll_for(entity, die_type, number_of_times, description, advantage: false, disadvantage: false)
    return nil unless @session.setting(:manual_dice_roll)

    prompt.say(t('dice_roll.prompt', description: description, name: entity.name.colorize(:green)))
    number_of_times.times.map do |index|
      if advantage || disadvantage
        2.times.map do |index|
          prompt.ask(t("dice_roll.roll_attempt_#{advantage ? 'advantage' : 'disadvantage'}", total: number_of_times, die_type: die_type,
                                                                                             number: index + 1)) do |q|
            q.in("1-#{die_type}")
          end
        end.map(&:to_i)
      else
        prompt.ask(t('dice_roll.roll_attempt', die_type: die_type, number: index + 1, total: number_of_times)) do |q|
          q.in("1-#{die_type}")
        end.to_i
      end
    end
  end

  def prompt_hit_die_roll(entity, die_types)
    prompt.select(t('dice_roll.hit_die_selection', name: entity.name)) do |menu|
      die_types.each do |t|
        menu.choice "d#{t}", t
      end
      menu.choice t('skip_hit_die'), :skip
    end
  end

  # Show action UI
  # @param action [Natural20::Action]
  # @param entity [Entity]
  def action_ui(action, entity)
    return :stop if action == :stop

    cont = action.build_map
    loop do
      param = cont.param&.map do |p|
        case (p[:type])
        when :look
          self
        when :movement
          move_path, jump_index = move_ui(entity, p)
          return nil if move_path.nil?

          [move_path, jump_index]
        when :target, :select_target
          targets = attack_ui(entity, action, p)
          return nil if targets.nil? || targets.empty?

          targets.first
        when :select_weapon
          action.using || action.npc_action
        when :select_item
          item = prompt.select("#{entity.name} use item", per_page: TTY_PROMPT_PER_PAGE) do |menu|
            entity.usable_items.each do |d|
              if d[:consumable]
                menu.choice "#{d[:label].colorize(:blue)} (#{d[:qty]})", d[:name]
              else
                menu.choice d[:label].colorize(:blue).to_s, d[:name]
              end
            end
            menu.choice t(:back).colorize(:blue), :back
          end

          return nil if item == :back

          item
        when :select_ground_items
          selected_items = prompt.multi_select("Items on the ground around #{entity.name}") do |menu|
            map.items_on_the_ground(entity).each do |ground_item|
              ground, items = ground_item
              items.each do |t|
                item_label = t("object.#{t.label}", default: t.label)
                menu.choice t('inventory.inventory_items', name: item_label, qty: t.qty), [ground, t]
              end
            end
          end

          return nil if selected_items.empty?

          item_selection = {}
          selected_items.each do |s_item|
            ground, item = s_item

            qty = how_many?(item)
            item_selection[ground] ||= []
            item_selection[ground] << [item, qty]
          end

          item_selection.map do |k, v|
            [k, v]
          end
        when :select_object
          item = prompt.select("#{entity.name} interact with") do |menu|
            entity.usable_objects(map, battle).each do |d|
              menu.choice d.name.humanize.to_s, d
            end
            menu.choice t(:back).colorize(:blue), :back
          end

          return nil if item == :back

          item
        when :select_items
          selected_items = prompt.multi_select(p[:label], per_page: TTY_PROMPT_PER_PAGE) do |menu|
            p[:items].each do |m|
              item_label = t("object.#{m.label}", default: m.label)
              if m.try(:equipped)
                menu.choice t('inventory.equiped_items', name: item_label), m
              else
                menu.choice t('inventory.inventory_items', name: item_label, qty: m.qty), m
              end
            end
            menu.choice t(:back).colorize(:blue), :back
          end

          return nil if selected_items.include?(:back)

          selected_items = selected_items.map do |m|
            count = how_many?(m)
            [m, count]
          end
          selected_items
        when :interact
          object_action = prompt.select("#{entity.name} will") do |menu|
            interactions = p[:target].available_interactions(entity)
            class_key = p[:target].class.to_s
            if interactions.is_a?(Array)
              interactions.each do |k|
                menu.choice t(:"object.#{class_key}.#{k}", default: k.to_s.humanize), k
              end
            else
              interactions.each do |k, options|
                label = options[:label] || t(:"object.#{class_key}.#{k}", default: k.to_s.humanize)
                if options[:disabled]
                  menu.choice label, k, disabled: options[:disabled_text]
                else
                  menu.choice label, k
                end
              end
            end
            menu.choice 'Back', :back
          end

          return nil if item == :back

          object_action
        when :show_inventory
          inventory_ui(entity)
        else
          raise "unknown #{p[:type]}"
        end
      end
      cont = cont.next.call(*param)
      break if param.nil?
    end
    @action = cont
  end

  def describe_map(map, line_of_sight: [])
    line_of_sight = [line_of_sight] unless line_of_sight.is_a?(Array)
    pov = line_of_sight.map(&:name).join(',')
    puts "Battle Map (#{map.size[0]}x#{map.size[1]}) #{map.feet_per_grid}ft per square, pov #{pov}:"
  end

  # Return moves by a player using the commandline UI
  # @param entity [Natural20::Entity] The entity to compute moves for
  # @param battle [Natural20::Battle] An instance of the current battle
  # @return [Array]
  def move_for(entity, battle)
    puts ''
    puts "#{entity.name}'s turn"
    puts '==============================='
    loop do
      describe_map(battle.map, line_of_sight: entity)
      puts @renderer.render(line_of_sight: entity)
      puts t(:character_status_line, hp: entity.hp, max_hp: entity.max_hp, total_actions: entity.total_actions(battle), bonus_action: entity.total_bonus_actions(battle),
                                     available_movement: entity.available_movement(battle), statuses: entity.statuses.to_a.join(','))

      action = prompt.select("#{entity.name} (#{entity.token&.first}) will", per_page: TTY_PROMPT_PER_PAGE,
                                                                             filter: true) do |menu|
        entity.available_actions(@session, battle).each do |action|
          menu.choice action.label, action
        end
        # menu.choice 'Console (Developer Mode)', :console
        menu.choice 'End'.colorize(:red), :end
      end

      if action == :console
        prompt.say('battle - battle object')
        prompt.say('entity - Current Player/NPC')
        prompt.say('@map - Current map')
        binding.pry
        next
      end

      return nil if action == :end

      action = action_ui(action, entity)
      next if action.nil?

      return action
    end
  end

  def game_loop
    Natural20::EventManager.set_context(battle, battle.current_party)

    result = battle.while_active do |entity|
      start_combat = false
      if battle.has_controller_for?(entity)
        cycles = 0
        loop do
          cycles += 1
          session.save_game(battle)
          action = battle.move_for(entity)
          if action.nil?
            unless battle.current_party.include?(entity)
              describe_map(battle.map, line_of_sight: battle.current_party)
              puts @renderer.render(line_of_sight: battle.current_party)
            end
            prompt.keypress(t(:end_turn, name: entity.name)) unless battle.current_party.include? entity
            break
          end

          battle.action!(action)
          battle.commit(action)

          if battle.check_combat
            start_combat = true
            break
          end
          break if action.nil?
        end
      end

      start_combat
    end
    prompt.keypress(t(:tpk)) if result == :tpk
    puts '------------'
    puts t(:battle_end, num: battle.round + 1)
  end

  # Starts a battle
  # @param chosen_characters [Array]
  def battle_ui(chosen_characters)
    battle.map.activate_map_triggers(:on_map_entry, nil, ui_controller: self)
    battle.register_players(chosen_characters, self)
    chosen_characters.each do |entity|
      entity.attach_handler(:opportunity_attack, self, :opportunity_attack_listener)
    end
    game_loop
  end

  def opportunity_attack_listener(battle, session, entity, map, event)
    entity_x, entity_y = map.position_of(entity)
    target_x, target_y = event[:position]

    distance = Math.sqrt((target_x - entity_x)**2 + (target_y - entity_y)**2).ceil

    possible_actions = entity.available_actions(session, battle, opportunity_attack: true).select do |s|
      weapon_details = session.load_weapon(s.using)
      distance <= weapon_details[:range]
    end

    return nil if possible_actions.blank?

    action = prompt.select(t('action.opportunity_attack', name: entity.name, target: event[:target].name)) do |menu|
      possible_actions.each do |a|
        menu.choice a.label, a
      end
      menu.choice t(:waive_opportunity_attack), :waive
    end

    return nil if action == :waive

    if action
      action.target = event[:target]
      action.as_reaction = true
      return action
    end

    nil
  end

  def show_message(message)
    puts ''
    prompt.keypress(message)
  end

  # @return [TTY::Prompt]
  def prompt
    @@prompt ||= if test_mode
                   TTY::Prompt::Test.new
                 else
                   TTY::Prompt.new
                 end
  end
end
