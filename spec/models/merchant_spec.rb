require "rails_helper"

RSpec.describe Merchant do
  it { is_expected.to validate_presence_of(:reference) }
  it { is_expected.to validate_presence_of(:email) }
  it {
    is_expected.to define_enum_for(:disbursement_frequency)
      .with_values(daily: "DAILY", weekly: "WEEKLY")
      .backed_by_column_of_type(:string)
      .validating
  }

  it "exposes frequency helpers" do
    daily = build(:merchant, disbursement_frequency: "DAILY")
    weekly = build(:merchant, disbursement_frequency: "WEEKLY", live_on: Date.new(2022, 9, 5))

    expect(daily).to be_daily
    expect(weekly).to be_weekly
    expect(weekly.live_on_weekday).to eq(1)
  end
end
