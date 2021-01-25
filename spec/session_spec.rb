RSpec.describe Natural20::Session do
  let(:session) { Natural20::Session.new }

  it "is valid" do
    expect(session).to be
  end

  it "can change settion settings" do
    session.update_settings(manual_dice_roll: true)
    expect(session.setting(:manual_dice_roll)).to be
  end
end