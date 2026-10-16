require "rails_helper"

RSpec.describe BackfillSettlementsJob do
  it "delegates to BackfillSettlements" do
    expect(BackfillSettlements).to receive(:call)

    described_class.perform_now
  end
end
