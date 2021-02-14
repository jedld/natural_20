RSpec.describe AiController::PriorityQueue do
  let(:priority_qeueue) { described_class.new }

  before do
    arr = [
      ['A', 10],
      ['B', 12],
      ['C', 1],
      ['D', 20],
      ['E', 2]
    ]
    arr.each do |item|
      priority_qeueue.add_node(item[0], item[1])
    end
  end

  specify do
    expect(priority_qeueue.pop_to_arr).to eq(%w[C E A B D])
  end

  specify 'with priority update' do
    priority_qeueue.update_priority('D', 3)
    expect(priority_qeueue.pop_to_arr).to eq(%w[C E D A B])
  end
end
