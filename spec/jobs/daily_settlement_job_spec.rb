require "rails_helper"

RSpec.describe DailySettlementJob do
  it "delegates to DailySettlementService" do
    expect(DailySettlementService).to receive(:call).with(as_of: Date.new(2022, 10, 1))

    described_class.perform_now(Date.new(2022, 10, 1))
  end
end
