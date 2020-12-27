# typed: false
class CommandlineUI
  attr_reader :battle, :map, :session

  # Creates an instance of a commandline UI helper
  # @param battle [Battle]
  # @param map [BattleMap]
  def initialize(battle, map)
    @battle = battle
    @session = battle.session
    @map = map
    @prompt = TTY::Prompt.new
  end

  # Create a attack target selection CLI UI
  # @param entity [Entity]
  # @param action [Action]
  # @option options range [Integer]
  def attack_ui(entity, action, options = {})
    selected_targets = []

    target = @prompt.select("#{entity.name} targets") do |menu|
      battle.valid_targets_for(entity, action, target_types: options[:target_types], range: options[:range]).each do |target|
        menu.choice target.name, target
      end
      menu.choice "Manual"
      menu.choice "Back", nil
    end

    return nil if target == "Back"

    if target == "Manual"
      targets = target_ui(entity, validation: lambda { |selected|
                                    selected_entities = map.thing_at(*selected)

                                    return false if selected_entities.empty?

                                    selected_entities.detect do |selected_entity|
                                      battle.valid_targets_for(entity, action, target_types: options[:target_types], range: options[:range], include_objects: true).include?(selected_entity)
                                    end
                                  })

      if targets.size > (options[:num_select].presence || 1)
        loop do
          target = @prompt.select("multiple targets at location(s) please select specific targets") do |menu|
            targets.each do |t|
              menu.choice t.name.to_s, t
            end
          end
          selected_targets << target
          break unless selected_targets.size < options[:num_select]
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

  # @param entity [Entity]
  def target_ui(entity, initial_pos: nil, num_select: 1, validation: nil)
    selected = []
    initial_pos ||= map.position_of(entity)
    new_pos = nil
    loop do
      puts "\e[H\e[2J"
      puts " "
      puts map.render(line_of_sight: entity, select_pos: initial_pos)
      @prompt.say(map.thing_at(*initial_pos).map(&:name).join(",").to_s)
      movement = @prompt.keypress("ESC- back, (wsad) - movement, x,space - select, r - reset")

      if movement == "w"
        new_pos = [initial_pos[0], initial_pos[1] - 1]
      elsif movement == "a"
        new_pos = [initial_pos[0] - 1, initial_pos[1]]
      elsif movement == "d"
        new_pos = [initial_pos[0] + 1, initial_pos[1]]
      elsif movement == "s"
        new_pos = [initial_pos[0], initial_pos[1] + 1]
      elsif ["x", " "].include? movement
        next if validation && !validation.call(new_pos)

        selected << initial_pos
      elsif movement == "r"
        new_pos = map.position_of(entity)
        next
      elsif movement == "\e"
        return []
      else
        next
      end

      next if new_pos.nil?
      next unless map.line_of_sight_for?(entity, *new_pos)

      initial_pos = new_pos

      break unless movement != "x"
    end

    selected.compact.map { |e| map.thing_at(*e) }
  end

  # @param entity [Entity]
  def move_ui(entity, options = {})
    path = [map.position_of(entity)]
    loop do
      puts "\e[H\e[2J"
      puts "movement #{map.movement_cost(entity, path).to_s.colorize(:green)}ft."
      puts " "
      puts map.render(line_of_sight: entity, path: path)
      movement = @prompt.keypress(" (wsadx) - movement, (qezc) diagonals, space/enter - confirm path, r - reset")

      if movement == "w"
        new_path = [path.last[0], path.last[1] - 1]
      elsif movement == "a"
        new_path = [path.last[0] - 1, path.last[1]]
      elsif movement == "d"
        new_path = [path.last[0] + 1, path.last[1]]
      elsif movement == "s" || movement == "x"
        new_path = [path.last[0], path.last[1] + 1]
      elsif movement == " " || movement == '\r'
        next unless map.placeable?(entity, *path.last, battle)

        return path
      elsif movement == "q"
        new_path = [path.last[0] - 1, path.last[1] - 1]
      elsif movement == "e"
        new_path = [path.last[0] + 1, path.last[1] - 1]
      elsif movement == "z"
        new_path = [path.last[0] - 1, path.last[1] + 1]
      elsif movement == "c"
        new_path = [path.last[0] + 1, path.last[1] + 1]
      elsif movement == "r"
        path = [map.position_of(entity)]
        next
      elsif movement == "\e"
        return nil
      else
        next
      end

      next if new_path[0].negative? || new_path[0] >= map.size[0] || new_path[1].negative? || new_path[1] >= map.size[1]

      if path.size > 1 && new_path == path[path.size - 2]
        path.pop
      elsif map.passable?(entity, *new_path, battle) && map.movement_cost(entity, path + [new_path]) <= (options[:as_dash] ? entity.speed : entity.available_movement(battle))
        path << new_path
      end
      break unless true
    end
  end

  def action_ui(action, entity)
    cont = action.build_map
    loop do
      param = cont.param&.map do |p|
        case (p[:type])
        when :movement
          move_path = move_ui(entity, p)
          return nil if move_path.nil?

          move_path
        when :target, :select_target
          targets = attack_ui(entity, action, p)
          return nil if targets.nil? || targets.empty?

          targets.first
        when :select_weapon
          action.using || action.npc_action
        when :select_item
          item = @prompt.select("#{entity.name} use item") do |menu|
            entity.usable_items.each do |d|
              if d[:consumable]
                menu.choice "#{d[:label].colorize(:blue)} (#{d[:qty]})", d[:name]
              else
                menu.choice d[:label].colorize(:blue).to_s, d[:name]
              end
            end
            menu.choice "Back", :back
          end

          return nil if item == :back

          item
        when :select_object
          item = @prompt.select("#{entity.name} interact with") do |menu|
            entity.usable_objects(map, battle).each do |d|
              menu.choice d.name.humanize.to_s, d
            end
            menu.choice "Back", :back
          end

          return nil if item == :back

          item
        when :interact
          object_action = @prompt.select("#{entity.name} will") do |menu|
            p[:target].available_actions(entity).each do |d|
              menu.choice d.to_s.humanize, d
            end
            menu.choice "Back", :back
          end

          return nil if item == :back

          object_action
        when :show_inventory
          @prompt.select("#{entity.name}'s Inventory") do |menu|
            entity.inventory.each do |item|
              menu.choice "#{item.label.call} x #{item.qty}", item.name
            end
          end
        else
          raise "unknown #{p[:type]}"
        end
      end
      cont = cont.next.call(*param)
      break if param.nil?
    end
    @action = cont
  end

  # Starts a battle
  # @param chosen_characters [Array]
  # @param chosen_enemies [Array]
  def battle_ui(chosen_characters, chosen_enemies)
    chosen_characters.each_with_index do |chosen_character, index|
      battle.add(chosen_character, :a, position: "spawn_point_#{index + 1}", token: chosen_character.name[0])
    end

    controller = AiController::Standard.new

    chosen_enemies.each_with_index do |item, index|
      controller.register_handlers_on(item)
      battle.add(item, :b, position: "spawn_point_#{index + 3}")
    end

    battle.start
    puts "Combat Order:"

    battle.combat_order.each_with_index do |entity, index|
      puts "#{index + 1}. #{entity.name}"
    end

    battle.while_active do |entity|
      puts ""
      puts "#{entity.name}'s turn"
      puts "==============================="
      if entity.npc?
        cycles = 0
        loop do
          cycles += 1
          action = controller.move_for(entity, battle)

          if action.nil?
            puts "#{entity.name}: End turn."
            break
          end

          battle.action!(action)
          battle.commit(action)
          break if action.nil?
        end
        puts map.render(line_of_sight: chosen_characters)
        @prompt.keypress("Press space or enter to continue", keys: %i[space return])
      else
        loop do
          puts map.render(line_of_sight: entity)
          puts "#{entity.hp}/#{entity.max_hp} actions: #{entity.total_actions(battle)} bonus action: #{entity.total_bonus_actions(battle)}, movement: #{entity.available_movement(battle)}"

          action = @prompt.select("#{entity.name} will") do |menu|
            entity.available_actions(@session, battle).each do |action|
              menu.choice action.label, action
            end
            menu.choice "End", :end
            menu.choice "Stop Battle", :stop
          end

          break if action == :end
          return if action == :stop

          action = action_ui(action, entity)
          next if action.nil?

          battle.action!(action)
          battle.commit(action)
          break unless true
        end
      end
    end

    puts "------------"
    puts "battle ended in #{battle.round + 1} rounds."
  end
end
