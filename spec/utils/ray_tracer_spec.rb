# typed: false
require "spec_helper"

RSpec.describe RayTracer do
  let(:session) { Natural20::Session.new }
  before do
    @battle_map = BattleMap.new(session, "fixtures/battle_sim_objects")
  end

  specify "returns ray traced squares" do
  end
end
