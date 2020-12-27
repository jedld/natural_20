class DashAction < MoveAction

  def build_map
    OpenStruct.new({
      action: self,
      param: [
        {
          type: :movement,
          as_dash: true,
        },
      ],
      next: ->(path) {
        self.move_path = path
        self.as_dash = true
        OpenStruct.new({
          param: nil,
          next: ->() { self },
        })
      },
    })
  end

  def self.can?(entity, battle)
    battle && entity.total_actions(battle) > 0
  end
end

class DashBonusAction < DashAction
  def self.can?(entity, battle)
    battle && entity.class_feature?('cunning_action') && entity.total_bonus_actions(battle) > 0
  end
end