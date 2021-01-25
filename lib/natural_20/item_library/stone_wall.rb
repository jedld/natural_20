module ItemLibrary
  # Represents a staple of DnD the concealed pit trap
  class StoneWall < Object
    def opaque?
      !dead?
    end

    def passable?
      dead?
    end

    def token
      return ['`'] if dead?

      ['#']
    end
  end
end