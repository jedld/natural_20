module Natural20
  module Web
    class JsonRenderer
      attr_accessor :battle, :map
      # @param map [Natural20::BattleMap]
      def initialize(map, battle = nil)
        @map = map
        @battle = battle
      end

      def render(line_of_sight: nil, path: [], select_pos: nil)
        @map.base_map.transpose.each_with_index.collect do |row, row_index|
          row.each_with_index.collect do |c, col_index|
            entity = @map.entity_at(col_index, row_index)
            shared_attributes = {
              x: col_index, y: row_index, difficult: @map.difficult_terrain?(entity, col_index, row_index)
            }
            if entity
              shared_attributes[:in_battle] = @battle && @battle.combat_order.include?(entity)
              m_x, m_y = @map.entities[entity]
              attributes = shared_attributes.merge({id: entity.entity_uid,  hp: entity.hp, max_hp: entity.max_hp, entity_size: entity.size  })
              if (m_x == col_index) && (m_y == row_index)
                attributes = attributes.merge(entity: entity.token_image, name: entity.label, dead: entity.dead?, unconscious: entity.unconscious? )
              end
              attributes
            else
              shared_attributes
            end
          end
        end
      end
    end
  end
end