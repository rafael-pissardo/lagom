require "rails_helper"

RSpec.describe YearlyAdjustmentAuditService do
  it "lists credits by the year they were recorded and the year of the fee" do
    merchant = create(:merchant, reference: "audit_co", live_on: Date.new(2022, 9, 1))
    september = create(:monthly_fee, merchant: merchant, year: 2022, month: 9, commissions_cents: 0, charged_cents: 100)
    travel_to Time.zone.local(2022, 10, 2) do
      create(:monthly_fee_adjustment, monthly_fee: september, commissions_cents: 40, credit_cents: 40)
    end
    travel_to Time.zone.local(2026, 10, 21) do
      create(:monthly_fee_adjustment, monthly_fee: september, commissions_cents: 70, credit_cents: 30)
    end

    rows = described_class.call

    expect(rows.map { |row| [ row.charged_year, row.reference_year, row.adjustments_count, row.credit_cents ] }).to eq([
      [ 2022, 2022, 1, 40 ],
      [ 2026, 2022, 1, 30 ]
    ])
  end

  it "groups adjustments that share the charged year and the reference year" do
    merchant = create(:merchant, reference: "grouped_co", live_on: Date.new(2022, 9, 1))
    september = create(:monthly_fee, merchant: merchant, year: 2022, month: 9, commissions_cents: 0, charged_cents: 100)
    october = create(:monthly_fee, merchant: merchant, year: 2022, month: 10, commissions_cents: 0, charged_cents: 100)
    travel_to Time.zone.local(2026, 10, 21) do
      create(:monthly_fee_adjustment, monthly_fee: september, commissions_cents: 70, credit_cents: 30)
      create(:monthly_fee_adjustment, monthly_fee: october, commissions_cents: 50, credit_cents: 20)
    end

    rows = described_class.call

    expect(rows.map { |row| [ row.charged_year, row.reference_year, row.adjustments_count, row.credit_cents ] }).to eq([
      [ 2026, 2022, 2, 50 ]
    ])
  end
end
