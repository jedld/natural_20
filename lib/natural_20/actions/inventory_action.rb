class InventoryAction < Action
  def self.can?(_entity, _battle)
    true
  end

  def build_map
    OpenStruct.new({
                     action: self,
                     param: [
                       {
                         type: :show_inventory
                       }
                     ],
                     next: lambda { |_path|
                             OpenStruct.new({
                                              param: nil,
                                              next: -> { self }
                                            })
                           }
                   })
  end
end
