require "natural_20/cli/inventory_ui"
require "natural_20/cli/character_builder"
require "natural_20/cli/action_ui"

class CommandlineUI < Natural20::Controller
  include Natural20::InventoryUI
  include Natural20::MovementHelper
  include Natural20::Cover
  include Natural20::ActionUI

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
      advantage_mod, adv_info = target_advantage_condition(battle, entity, target, weapon)
      adv_details, disadv_details = adv_info
      target_labels << t(:with_advantage) if advantage_mod.positive?
      target_labels << t(:with_disadvantage) if advantage_mod.negative?

      reasons = []
      adv_details.each do |d|
        reasons << "+#{t("attack_status.#{d}")}".colorize(:blue)
      end
      disadv_details.each do |d|
        reasons << "-#{t("attack_status.#{d}")}".colorize(:red)
      end

      target_labels << reasons.join(",")
    end
    target_labels.join(" ")
  end

  def self.clear_screen
    puts "\e[H\e[2J"
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
      puts Benchmark.measure {
        puts @renderer.render(entity: entity, line_of_sight: entity, path: path, update_on_drop: true,
                              acrobatics_checks: movement.acrobatics_check_locations, athletics_checks: movement.athletics_check_locations)
      }
      prompt.say("(warning) token cannot end its movement in this square") unless @map.placeable?(entity, *path.last,
      battle)
      prompt.say("(warning) need to perform a jump over this terrain") if @map.jump_required?(entity, *path.last)
      directions = []
      directions << "(wsadx) - movement, (qezc) diagonals"
      directions << "j - toggle jump" unless entity.prone?
      directions << "space/enter - confirm path"
      directions << "r - reset"
      movement = prompt.keypress(directions.join(","))

      if movement == "w"
        new_path = [path.last[0], path.last[1] - 1]
      elsif movement == "a"
        new_path = [path.last[0] - 1, path.last[1]]
      elsif movement == "d"
        new_path = [path.last[0] + 1, path.last[1]]
      elsif %w[s x].include?(movement)
        new_path = [path.last[0], path.last[1] + 1]
      elsif [" ", "\r"].include?(movement)
        next unless valid_move_path?(entity, path, battle, @map, manual_jump: jump_index)

        return [path, jump_index]
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
        jump_index = []
        toggle_jump = false
        next
      elsif movement == "j" && !entity.prone?
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

    prompt.say(t("dice_roll.prompt", description: description, name: entity.name.colorize(:green)))
    number_of_times.times.map do |index|
      if advantage || disadvantage
        2.times.map do |index|
          prompt.ask(t("dice_roll.roll_attempt_#{advantage ? "advantage" : "disadvantage"}", total: number_of_times, die_type: die_type,
                                                                                             number: index + 1)) do |q|
            q.in("1-#{die_type}")
          end
        end.map(&:to_i)
      else
        prompt.ask(t("dice_roll.roll_attempt", die_type: die_type, number: index + 1, total: number_of_times)) do |q|
          q.in("1-#{die_type}")
        end.to_i
      end
    end
  end

  def prompt_hit_die_roll(entity, die_types)
    prompt.select(t("dice_roll.hit_die_selection", name: entity.name, hp: entity.hp, max_hp: entity.max_hp)) do |menu|
      die_types.each do |t|
        menu.choice "d#{t}", t
      end
      menu.choice t("skip_hit_die"), :skip
    end
  end

  def arcane_recovery_ui(entity, spell_levels)
    choice = prompt.select(t("action.arcane_recovery", name: entity.name)) do |q|
      spell_levels.sort.each do |level|
        q.choice t(:spell_level, level: level), level
      end
      q.choice t("action.waive_arcane_recovery"), :waive
    end
    return nil if choice == :waive

    choice
  end

  def spell_slots_ui(entity)
    puts t(:spell_slots)
    (1..9).each do |level|
      next unless entity.max_spell_slots(level).positive?

      used_slots = entity.max_spell_slots(level) - entity.spell_slots(level)
      used = used_slots.times.map do
        "■"
      end

      avail = entity.spell_slots(level).times.map do
        "°"
      end

      puts t(:spell_level_slots, level: level, slots: (used + avail).join(" "))
    end
  end

  def describe_map(map, line_of_sight: [])
    line_of_sight = [line_of_sight] unless line_of_sight.is_a?(Array)
    pov = line_of_sight.map(&:name).join(",")
    puts t("map_description", width: map.size[0], length: map.size[1], feet_per_grid: map.feet_per_grid, pov: pov)
  end

  # Return moves by a player using the commandline UI
  # @param entity [Natural20::Entity] The entity to compute moves for
  # @param battle [Natural20::Battle] An instance of the current battle
  # @return [Array]
  def move_for(entity, battle)
    puts ""
    puts "#{entity.name}'s turn"
    puts "==============================="
    loop do
      describe_map(battle.map, line_of_sight: entity)
      puts @renderer.render(line_of_sight: entity)

      puts t(:character_status_line, ac: entity.armor_class, hp: entity.hp, max_hp: entity.max_hp, total_actions: entity.total_actions(battle), bonus_action: entity.total_bonus_actions(battle),
                                     available_movement: entity.available_movement(battle), statuses: entity.statuses.to_a.join(","))
      entity.active_effects.each do |effect|
        puts t(:effect_line, effect_name: effect[:effect].label, source: effect[:source].name)
      end
      action = prompt.select(t("character_action_prompt", name: entity.name, token: entity.token&.first), per_page: TTY_PROMPT_PER_PAGE,
                                                                                                          filter: true) do |menu|
        entity.available_actions(@session, battle).each do |a|
          menu.choice a.label, a
        end
        # menu.choice 'Console (Developer Mode)', :console
        menu.choice "End".colorize(:red), :end
      end

      if action == :console
        prompt.say("battle - battle object")
        prompt.say("entity - Current Player/NPC")
        prompt.say("@map - Current map")
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
        move_path = []
        loop do
          cycles += 1
          session.save_game(battle)
          action = battle.move_for(entity)
          if action.nil?
            unless battle.current_party.include?(entity)
              describe_map(battle.map, line_of_sight: battle.available_party_members)
              puts @renderer.render(line_of_sight: battle.available_party_members, path: move_path)
            end
            prompt.keypress(t(:end_turn, name: entity.name)) unless battle.current_party.include? entity
            move_path = []
            break
          end

          move_path += action.move_path if action.is_a?(MoveAction)

          battle.action!(action)
          battle.commit(action)

          if battle.check_combat
            start_combat = true
            break
          end
          break if action.nil? || entity.unconscious?
        end
      end

      start_combat
    end
    prompt.keypress(t(:tpk)) if result == :tpk
    puts "------------"
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

    distance = Math.sqrt((target_x - entity_x) ** 2 + (target_y - entity_y) ** 2).ceil

    possible_actions = entity.available_actions(session, battle, opportunity_attack: true).select do |s|
      weapon_details = session.load_weapon(s.using)
      distance <= weapon_details[:range]
    end

    return nil if possible_actions.blank?

    action = prompt.select(t("action.opportunity_attack", name: entity.name, target: event[:target].name)) do |menu|
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
    puts ""
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
