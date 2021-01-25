module Natural20::Container
  # @param battle [Natural20::Battle]
  # @param source [Natural20::Entity]
  # @param target [Natural20::Entity]
  # @param items [Array]
  def store(battle, source, target, items)
    items.each do |item_with_count|
      item, qty = item_with_count
      source_item = source.deduct_item(item.name, qty)
      target.add_item(item.name, qty, source_item)
      battle.trigger_event!(:object_received, target, item_type: item.name)
    end
  end

  # @param battle [Natural20::Battle]
  # @param source [Natural20::Entity]
  # @param target [Natural20::Entity]
  # @param items [Array]
  def retrieve(battle, source, target, items)
    items.each do |item_with_count|
      item, qty = item_with_count
      if item.equipped
        unequip(item.name, transfer_inventory: false)
        source.add_item(item.name)
      else
        source_item = target.deduct_item(item.name, qty)
        source.add_item(item.name, qty, source_item)
        battle.trigger_event!(:object_received, source, item_type: item.name)
      end
    end
  end
end
