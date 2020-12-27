class UseItemAction < Action
  attr_accessor :target, :target_item
  def self.can?(entity, battle)
    battle.nil? || entity.total_actions(battle).positive?
  end

  def self.build(session, source)
    action = UseItemAction.new(session, source, :attack)
    action.build_map
  end

  def build_map
    OpenStruct.new({
      action: self,
      param: [
        {
          type: :select_item
        }
      ],
      next: ->(item) {
        item_details = Session.load_equipment(item)
        raise "item #{item_details[:name]} not usable!" unless item_details[:usable]

        @target_item = item_details[:item_class].constantize.new(item, item_details)
        @target_item.build_map(self)
      }
    })
  end

  def resolve(session, map = nil, opts = {})
    battle = opts[:battle]
    result_payload = {
      source: @source,
      target: target,
      map: map,
      battle: battle,
      type: :use_item,
      item: target_item
    }.merge(target_item.resolve)
    @result = [result_payload]
    self
  end

  def apply!(battle)
    @result.each do |item|
      case (item[:type])
      when :use_item
        EventManager.received_event({event: :use_item, source: item[:source], item: item[:item]})
        item[:item].use!(item[:target], item)
        item[:source].deduct_item(item[:item].name, 1) if item[:item].consumable?
        battle.entity_state_for(item[:source])[:action] -= 1 if battle
      end
    end
  end
end