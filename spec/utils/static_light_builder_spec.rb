# typed: false
require 'spec_helper'

RSpec.describe Natural20::StaticLightBuilder do
  let(:session) { Natural20::Session.new }
  let(:map) { Natural20::BattleMap.new(session, 'fixtures/battle_sim') }
  let(:fixture) { described_class.new(map) }

  before do
    brazier_object = session.load_object('brazier')
    map.place_object(brazier_object, 0, 0)
  end

  specify '#lights' do
    expect(fixture.lights).to eq([{ bright: 10, dim: 5, position: [2, 1] },
                                  { bright: 10, dim: 5, position: [2, 5] }])
  end

  specify '#build_map' do
    expect(fixture.build_map.transpose).to eq(
      [[0.5, 1.0, 1.0, 1.0, 0.0, 0.0],
       [1.0, 1.0, 1.0, 1.0, 0.0, 0.0],
       [1.0, 1.0, 1.0, 1.0, 0.5, 0.5],
       [1.0, 1.0, 1.0, 2.0, 2.0, 0.0],
       [0.5, 1.5, 1.5, 1.5, 1.5, 1.0],
       [1.0, 1.0, 1.0, 1.0, 1.0, 0.5],
       [1.0, 1.0, 1.0, 1.0, 0.5, 0.5]])
  end

  specify '#light_at' do
    expect(fixture.light_at(0, 0)).to eq(1.0)
  end
end
