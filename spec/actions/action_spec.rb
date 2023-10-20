RSpec.describe Natural20::Action do

    specify ".to_type" do
        expect(Natural20::Action.to_type("AttackAction")).to be :attack
    end
   
end