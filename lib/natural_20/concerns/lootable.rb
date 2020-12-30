module Natural20::Lootable
  # Lists default available interactions for an entity
  # @return [Array] List of availabel actions
  def available_interactions(entity, battle = nil)
    other_interactions = super entity, battle

    if (dead? || unconcious?) && !inventory.empty?
      other_interactions << :loot
    end

    other_interactions
  end
end
