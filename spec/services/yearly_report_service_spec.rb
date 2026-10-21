require "rails_helper"

RSpec.describe YearlyReportService do
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
    expect(rows.first.monthly_fees_charged_cents).to eq(5)
    expect(rows.first.monthly_fee_adjustments_cents).to eq(0)
    expect(rows.first.monthly_fees_amount_cents).to eq(5)
  end

  it "counts an adjustment in the year it was recorded and subtracts it from that year's charged amount" do
    merchant = create(:merchant, reference: "adjust_co", live_on: Date.new(2022, 9, 1), minimum_monthly_fee_cents: 100)
    september = create(:monthly_fee, merchant: merchant, year: 2022, month: 9, commissions_cents: 0, charged_cents: 100)
    create(:monthly_fee, merchant: merchant, year: 2022, month: 10, commissions_cents: 200, charged_cents: 0)
    travel_to Time.zone.local(2022, 10, 2) do
      create(:monthly_fee_adjustment, monthly_fee: september, commissions_cents: 40, credit_cents: 40)
    end
    travel_to Time.zone.local(2026, 10, 21) do
      create(:monthly_fee_adjustment, monthly_fee: september, commissions_cents: 70, credit_cents: 30)
    end

    rows = described_class.call.index_by(&:year)

    expect(rows[2022].monthly_fees_charged_cents).to eq(100)
    expect(rows[2022].monthly_fee_adjustments_cents).to eq(40)
    expect(rows[2022].monthly_fees_amount_cents).to eq(60)
    expect(rows[2026].monthly_fees_count).to eq(0)
    expect(rows[2026].monthly_fees_charged_cents).to eq(0)
    expect(rows[2026].monthly_fee_adjustments_cents).to eq(30)
    expect(rows[2026].monthly_fees_amount_cents).to eq(-30)
  end

  it "counts a 31/12 order disbursed on 01/01 in the next year, and the December fee in 2022" do
    merchant = create(:merchant, reference: "nye_co", live_on: Date.new(2022, 12, 1), minimum_monthly_fee_cents: 100)
    create(:order, merchant: merchant, ordered_on: Date.new(2022, 12, 31), amount_cents: 5_000)

    SettleMerchantsService.call(frequency: "DAILY", as_of: Date.new(2023, 1, 1))

    rows = described_class.call.index_by(&:year)

    expect(rows[2022].disbursements_count).to eq(0)
    expect(rows[2022].amount_disbursed_cents).to eq(0)
    expect(rows[2022].order_fees_cents).to eq(0)
    expect(rows[2022].monthly_fees_count).to eq(1)
    expect(rows[2022].monthly_fees_charged_cents).to eq(52)
    expect(rows[2022].monthly_fee_adjustments_cents).to eq(0)
    expect(rows[2022].monthly_fees_amount_cents).to eq(52)
    expect(rows[2023].disbursements_count).to eq(1)
    expect(rows[2023].amount_disbursed_cents).to eq(4_952)
    expect(rows[2023].order_fees_cents).to eq(48)
    expect(rows[2023].monthly_fees_count).to eq(0)
    expect(rows[2024]).to be_nil
  end
end
