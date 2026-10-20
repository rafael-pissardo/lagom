require "rails_helper"

RSpec.describe BackfillSettlements do
  it "backfills disbursements through the catch-up window and closed monthly fees" do
    merchant = create(
      :merchant,
      reference: "backfill_co",
      live_on: Date.new(2022, 9, 1),
      disbursement_frequency: "DAILY",
      minimum_monthly_fee_cents: 100
    )
    create(:order, merchant: merchant, ordered_on: Date.new(2022, 9, 1), amount_cents: 5_000)

    described_class.call(as_of: Date.new(2022, 9, 15))

    expect(Disbursement.where(merchant: merchant).order(:disbursed_on).pluck(:disbursed_on, :reference)).to eq([
      [ Date.new(2022, 9, 2), "backfill_co20220902" ]
    ])
    expect(MonthlyFee.find_by(merchant: merchant, year: 2022, month: 8)).to be_nil
    expect(MonthlyFee.find_by(merchant: merchant, year: 2022, month: 9)).to be_nil
  end

  it "charges closed months when as_of is after month end" do
    merchant = create(
      :merchant,
      reference: "backfill_fee",
      live_on: Date.new(2022, 9, 1),
      disbursement_frequency: "DAILY",
      minimum_monthly_fee_cents: 100
    )
    create(:order, merchant: merchant, ordered_on: Date.new(2022, 9, 10), amount_cents: 5_000)

    described_class.call(as_of: Date.new(2022, 10, 5))

    fee = MonthlyFee.find_by!(merchant: merchant, year: 2022, month: 9)
    expect(fee.charged_cents).to eq(52)
  end
end
