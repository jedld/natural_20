module Natural20
  class Session
    def load_characters
      files = Dir[File.join(File.dirname(__FILE__), "..", "characters", "*.yml")]
      @characters ||= files.map do |file|
        YAML.load_file(file)
      end
      @characters.map do |char_content|
        PlayerCharacter.new(char_content)
      end
    end

    def load_npcs
      files = Dir[File.join(File.dirname(__FILE__), "..", "npcs", "*.yml")]
      files.map do |fname|
        npc_name = File.basename(fname, ".yml")
        Npc.new(npc_name, rand_life: true)
      end
    end

    def self.load_weapon(weapon)
      @weapons ||= YAML.load_file(File.join(File.dirname(__FILE__), "..", "items", "weapons.yml")).deep_symbolize_keys!
      @weapons[weapon.to_sym]
    end

    def self.load_equipment(item)
      @equipment ||= YAML.load_file(File.join(File.dirname(__FILE__), "..", "items", "equipment.yml")).deep_symbolize_keys!
      @equipment[item.to_sym]
    end

    def self.load_object(object_name)
      @objects ||= YAML.load_file(File.join(File.dirname(__FILE__), "..", "items", "objects.yml")).deep_symbolize_keys!
      raise "cannot find #{object_name}" unless @objects.key?(object_name.to_sym)

      @objects[object_name.to_sym]
    end
  end
end
