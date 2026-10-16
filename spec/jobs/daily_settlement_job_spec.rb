require "rails_helper"

RSpec.describe DailySettlementJob do
  it "delegates to DailySettlement" do
    expect(DailySettlement).to receive(:call).with(as_of: Date.new(2022, 10, 1))

    described_class.perform_now(Date.new(2022, 10, 1))
  end
end
