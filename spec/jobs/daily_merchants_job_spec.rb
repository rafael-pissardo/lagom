require "rails_helper"

RSpec.describe DailyMerchantsJob do
  it "settles daily merchants for the given day" do
    expect(SettleMerchantsService).to receive(:call).with(frequency: "DAILY", as_of: Date.new(2022, 10, 1))

    described_class.perform_now(Date.new(2022, 10, 1))
  end

  it "uses today when no date is given" do
    travel_to Time.zone.parse("2022-10-01 07:00") do
      expect(SettleMerchantsService).to receive(:call).with(frequency: "DAILY", as_of: Date.new(2022, 10, 1))

      described_class.perform_now
    end
  end
end
