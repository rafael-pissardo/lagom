require "rails_helper"

RSpec.describe ReplaySettlementService do
  it "pays that year's orders on the day the job would have run and leaves the next year pending" do
    merchant = create(:merchant, reference: "replay_daily", live_on: Date.new(2022, 12, 1), disbursement_frequency: "DAILY", minimum_monthly_fee_cents: 0)
    create(:order, merchant:, ordered_on: Date.new(2022, 12, 30), amount_cents: 1_000, commission_cents: 10)
    create(:order, merchant:, ordered_on: Date.new(2022, 12, 31), amount_cents: 2_000, commission_cents: 20)
    later = create(:order, merchant:, ordered_on: Date.new(2023, 1, 2), amount_cents: 4_000, commission_cents: 40)

    described_class.call(year: 2022)

    expect(Disbursement.where(merchant:).order(:disbursed_on).pluck(:disbursed_on, :gross_cents)).to eq([
      [ Date.new(2022, 12, 31), 1_000 ],
      [ Date.new(2023, 1, 1), 2_000 ]
    ])
    expect(later.reload.disbursement_id).to be_nil
  end

  it "pays a weekly order on the next weekday after the year ends" do
    merchant = create(:merchant, :weekly, reference: "replay_week", live_on: Date.new(2022, 12, 5), minimum_monthly_fee_cents: 0)
    order = create(:order, merchant:, ordered_on: Date.new(2022, 12, 31), amount_cents: 1_000, commission_cents: 10)

    described_class.call(year: 2022)

    expect(Disbursement.find_by!(merchant:).disbursed_on).to eq(Date.new(2023, 1, 2))
    expect(order.reload.disbursement_id).to eq(Disbursement.find_by!(merchant:).id)
  end

  it "charges months through December of that year and not the next January" do
    merchant = create(:merchant, reference: "replay_fee", live_on: Date.new(2022, 11, 1), minimum_monthly_fee_cents: 100)
    create(:order, merchant:, ordered_on: Date.new(2022, 12, 15), amount_cents: 1_000, commission_cents: 10)

    described_class.call(year: 2022)

    expect(MonthlyFee.where(merchant:).order(:month).pluck(:year, :month)).to eq([
      [ 2022, 11 ],
      [ 2022, 12 ]
    ])
  end

  it "does not disburse an order from a later year when that is the only pending order" do
    merchant = create(:merchant, reference: "replay_future", live_on: Date.new(2022, 1, 1), minimum_monthly_fee_cents: 0)
    later = create(:order, merchant:, ordered_on: Date.new(2024, 2, 1), amount_cents: 1_000, commission_cents: 10)

    described_class.call(year: 2022)

    expect(Disbursement.where(merchant:)).to be_empty
    expect(later.reload.disbursement_id).to be_nil
  end

  it "does not create a second disbursement or monthly fee when run again" do
    merchant = create(:merchant, reference: "replay_twice", live_on: Date.new(2022, 12, 1), minimum_monthly_fee_cents: 100)
    create(:order, merchant:, ordered_on: Date.new(2022, 12, 30), amount_cents: 1_000, commission_cents: 10)

    described_class.call(year: 2022)
    described_class.call(year: 2022)

    expect(Disbursement.where(merchant:).count).to eq(1)
    expect(MonthlyFee.where(merchant:).count).to eq(1)
  end
end
