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
          targets = attack_ui(entity, action, p)
          return nil if targets.nil? || targets.empty?

          p[:num] > 1 ? targets : targets.first
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
end
