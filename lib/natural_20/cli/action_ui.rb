module Natural20::ActionUI
  TTY_PROMPT_PER_PAGE = 20

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
          if p[:target_types] == :square
           target_ui(entity, range: p[:range], num_select: p[:num_select], target_mode: :square)
          else
            targets = attack_ui(entity, action, p)
            return nil if targets.nil? || targets.empty?

            p[:num] > 1 ? targets : targets.first
          end
        when :select
          prompt.select(:"select_items", label: p[:label]) do |q|
            p[:choices].each do |choice|
              q.choice choice[1], choice[0]
            end
          end
        when :select_spell
          spell_slots_ui(entity)

          spell = prompt.select("#{entity.name} cast Spell", per_page: TTY_PROMPT_PER_PAGE) do |q|
            spell_choice(entity, battle, q)
            q.choice t(:back).colorize(:blue), :back
          end

          return nil if spell == :back

          spell
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
          target_objects = entity.usable_objects(map, battle)
          item = prompt.select("#{entity.name} interact with") do |menu|
            target_objects.each do |d|
              menu.choice d.name.humanize.to_s, d
            end
            menu.choice t(:manual_target), :manual_target
            menu.choice t(:back).colorize(:blue), :back
          end

          return nil if item == :back

          if item == :manual_target
            item = target_ui(entity, num_select: 1, validation: lambda { |selected|
              selected_entities = map.thing_at(*selected)

              return false if selected_entities.empty?

              selected_entities.detect do |selected_entity|
                target_objects.include?(selected_entity)
              end
            }).first
          end

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

  def spell_choice(entity, battle, menu)
    entity.spell_list(battle).each do |k, details|
      available_levels = if details[:higher_level]
                           (details[:level]..9).select { |lvl| entity.max_spell_slots(lvl).positive? }
                         else
                           [details[:level]]
                         end
      available_levels.each do |spell_level|
        level_str = spell_level.zero? ? 'cantrip' : "lvl. #{spell_level}"
        choice_label = t(:"action.spell_choice", spell: t("spell.#{k}"), level: level_str,
                                                 description: details[:description])
        if details[:disabled].empty?
          menu.choice(choice_label, [k, spell_level])
        else
          disable_reason = details[:disabled].map { |d| t("spells.disabled.#{d}") }.join(', ')
          menu.choice(choice_label, k, disabled: disable_reason)
        end
      end
    end
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
    total_targets = options[:num] || 1
    puts t(:multiple_targets, total_targets: total_targets) if total_targets > 1
    total_targets.times.each do |index|
      target = prompt.select("Target #{index + 1}: #{entity.name} targets") do |menu|
        valid_targets.each do |t|
          menu.choice target_name(entity, t, weapon: weapon_details), t
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
        selected_targets += target_ui(entity, weapon: weapon_details, validation: lambda { |selected|
                                                                                    selected_entities = map.thing_at(*selected)

                                                                                    if selected_entities.empty?
                                                                                      return false
                                                                                    end

                                                                                    selected_entities.detect do |selected_entity|
                                                                                      valid_targets.include?(selected_entity)
                                                                                    end
                                                                                  })
      end

      selected_targets << target
    end

    selected_targets.flatten
  end

  # @param entity [Natural20::Entity]
  def target_ui(entity, initial_pos: nil, num_select: 1, validation: nil, perception: 10, range: nil, weapon: nil, look_mode: false, target_mode: :entity)
    selected = []
    initial_pos ||= map.position_of(entity)
    new_pos = nil
    loop do
      CommandlineUI.clear_screen
      highlights = map.highlight(entity, perception)
      prompt.say(t('perception.looking_around', perception: perception))
      describe_map(battle.map, line_of_sight: entity)
      puts @renderer.render(line_of_sight: entity, select_pos: initial_pos, highlight: highlights, range: range)
      puts "\n"
      things = map.thing_at(*initial_pos, reveal_concealed: true)

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

          thing.active_effects.each do |effect|
            puts "  #{t(:effect_line, effect_name: effect[:effect].label, source: effect[:source].name)}"
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
      elsif ['x', ' ', "\r"].include? movement
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

      break if ['x', ' ', "\r"].include? movement
    end

    if target_mode == :square
      selected
    else
      selected = selected.compact.map { |e| map.thing_at(*e) }
      selected_targets = []
      targets = selected.flatten.select { |t| t.hp && t.hp.positive? }.flatten.uniq

      if targets.size > 1
        loop do
          target = prompt.select(t('multiple_target_prompt')) do |menu|
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

      return nil if selected_targets.blank?

      selected_targets
    end
  end
end
