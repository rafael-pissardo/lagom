require "rails_helper"

RSpec.describe DailySettlement do
  it "disburses eligible merchants and charges monthly fees on the first day" do
    merchant = create(:merchant, reference: "daily_settle", live_on: Date.new(2022, 9, 1), disbursement_frequency: "DAILY", minimum_monthly_fee_cents: 100)
    create(:order, merchant: merchant, ordered_on: Date.new(2022, 9, 30), amount_cents: 5_000)

    described_class.call(as_of: Date.new(2022, 10, 1))

    expect(Disbursement.find_by(merchant: merchant, disbursed_on: Date.new(2022, 10, 1))).to be_present
    fee = MonthlyFee.find_by!(merchant: merchant, year: 2022, month: 9)
    expect(fee.charged_cents).to eq(52)
  end
end
