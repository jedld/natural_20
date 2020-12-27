# typed: true
module Natural20
  class Session
    attr_reader :root_path

    def initialize(root_path = nil)
      @root_path = root_path.presence || "."
    end

    def load_characters
      files = Dir[File.join(@root_path, "characters", "*.yml")]
      @characters ||= files.map do |file|
        YAML.load_file(file)
      end
      @characters.map do |char_content|
        PlayerCharacter.new(self, char_content)
      end
    end

    def npc(npc_type, options = {})
      Npc.new(self, npc_type, options)
    end

    def load_npcs
      files = Dir[File.join(@root_path, "npcs", "*.yml")]
      files.map do |fname|
        npc_name = File.basename(fname, ".yml")
        Npc.new(self, npc_name, rand_life: true)
      end
    end

    def load_weapon(weapon)
      @weapons ||= YAML.load_file(File.join(@root_path, "items", "weapons.yml")).deep_symbolize_keys!
      @weapons[weapon.to_sym]
    end

    def load_equipment(item)
      @equipment ||= YAML.load_file(File.join(@root_path, "items", "equipment.yml")).deep_symbolize_keys!
      @equipment[item.to_sym]
    end

    def load_object(object_name)
      @objects ||= YAML.load_file(File.join(@root_path, "items", "objects.yml")).deep_symbolize_keys!
      raise "cannot find #{object_name}" unless @objects.key?(object_name.to_sym)

      @objects[object_name.to_sym]
    end
  end
end
