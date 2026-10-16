require "rails_helper"

RSpec.describe YearlyReport do
  it "aggregates disbursements and charged monthly fees by year" do
    merchant = create(:merchant, reference: "report_co", live_on: Date.new(2022, 9, 1), minimum_monthly_fee_cents: 100)
    create(
      :disbursement,
      merchant: merchant,
      disbursed_on: Date.new(2022, 9, 5),
      reference: "report_co20220905",
      gross_cents: 10_000,
      commission_cents: 95,
      net_cents: 9_905
    )
    create(:monthly_fee, merchant: merchant, year: 2022, month: 9, commissions_cents: 95, charged_cents: 5)
    create(:monthly_fee, merchant: merchant, year: 2022, month: 10, commissions_cents: 200, charged_cents: 0)

    rows = described_class.call

    expect(rows.size).to eq(1)
    expect(rows.first.year).to eq(2022)
    expect(rows.first.disbursements_count).to eq(1)
    expect(rows.first.amount_disbursed_cents).to eq(9_905)
    expect(rows.first.order_fees_cents).to eq(95)
    expect(rows.first.monthly_fees_count).to eq(1)
    expect(rows.first.monthly_fees_amount_cents).to eq(5)
  end
end
