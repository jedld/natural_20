module Natural20
  # Concerns used for objects that can have notes
  module Notable
    # List notes on object
    # @param entity [Natural20::Entity]
    # @param perception [Integer]
    # @return [Array]
    def list_notes(entity, perception, highlight: false)
      @properties[:notes]&.map do |note|
        next if highlight && !note[:highlight]
        next if note[:if].presence && !eval_if(note[:if])

        perception_dc = note[:perception_dc] || 0
        if perception >= perception_dc
          note_language = note[:language].presence

          result = if note_language
                     note_content = if entity.languages.include?(note_language)
                                      note[:note]
                                    else
                                      '???'
                                    end
                     t('perception.note_with_language', note_language: note_language, note: note_content)
                   else
                     note[:note]
                   end

          if perception_dc.positive?
            t('perception.passed', note: result)
          else
            result
          end
        end
      end&.compact || []
    end
  end
end
