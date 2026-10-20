require "rails_helper"

RSpec.describe BackfillSettlementsService do
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

  it "groups a clean daily merchant in SQL, one disbursement per day with its own total, skipping empty days" do
    merchant = create(:merchant, reference: "grouped_co", live_on: Date.new(2022, 9, 1), minimum_monthly_fee_cents: 0)
    first = create(:order, merchant:, ordered_on: Date.new(2022, 9, 1), amount_cents: 1_000, commission_cents: 10)
    third = create(:order, merchant:, ordered_on: Date.new(2022, 9, 3), amount_cents: 3_000, commission_cents: 30)

    expect(DisburseMerchantService).not_to receive(:call)

    described_class.call(as_of: Date.new(2022, 9, 10))

    rows = Disbursement.where(merchant:).order(:disbursed_on).pluck(:disbursed_on, :reference, :gross_cents, :commission_cents, :net_cents)
    expect(rows).to eq([
      [ Date.new(2022, 9, 2), "grouped_co20220902", 1_000, 10, 990 ],
      [ Date.new(2022, 9, 4), "grouped_co20220904", 3_000, 30, 2_970 ]
    ])
    expect(disbursed_on_for(first)).to eq(Date.new(2022, 9, 2))
    expect(disbursed_on_for(third)).to eq(Date.new(2022, 9, 4))
  end

  it "groups a weekly merchant's orders on the next live_on weekday" do
    merchant = create(:merchant, :weekly, reference: "weekly_co", live_on: Date.new(2022, 9, 5), minimum_monthly_fee_cents: 0)
    create(:order, merchant:, ordered_on: Date.new(2022, 9, 6), amount_cents: 1_000, commission_cents: 10)
    create(:order, merchant:, ordered_on: Date.new(2022, 9, 10), amount_cents: 2_000, commission_cents: 20)

    described_class.call(as_of: Date.new(2022, 9, 10))

    expect(Disbursement.where(merchant:).pluck(:disbursed_on, :reference, :gross_cents, :commission_cents, :net_cents)).to eq([
      [ Date.new(2022, 9, 12), "weekly_co20220912", 3_000, 30, 2_970 ]
    ])
    expect(Order.where(merchant:).undisbursed).to be_empty
  end

  it "leaves an order alone when its disbursement day falls after as_of + 7" do
    merchant = create(:merchant, reference: "late_co", live_on: Date.new(2022, 9, 1), minimum_monthly_fee_cents: 0)
    late = create(:order, merchant:, ordered_on: Date.new(2022, 9, 20), amount_cents: 1_000, commission_cents: 10)

    described_class.call(as_of: Date.new(2022, 9, 10))

    expect(Disbursement.where(merchant:)).to be_empty
    expect(late.reload.disbursement_id).to be_nil
  end

  it "does not duplicate disbursements or fees when it runs again" do
    merchant = create(:merchant, reference: "twice_co", live_on: Date.new(2022, 9, 1), minimum_monthly_fee_cents: 100)
    create(:order, merchant:, ordered_on: Date.new(2022, 9, 1), amount_cents: 1_000, commission_cents: 10)

    described_class.call(as_of: Date.new(2022, 10, 5))
    described_class.call(as_of: Date.new(2022, 10, 5))

    expect(Disbursement.where(merchant:).count).to eq(1)
    expect(MonthlyFee.where(merchant:).count).to eq(1)
    expect(Order.where(merchant:).undisbursed).to be_empty
  end

  it "moves an order whose natural day is taken to the next open day, with only its own total" do
    merchant = create(:merchant, reference: "taken_co", live_on: Date.new(2022, 9, 1), minimum_monthly_fee_cents: 0)
    taken = create(:disbursement, merchant:, disbursed_on: Date.new(2022, 9, 2), gross_cents: 1_000, commission_cents: 10, net_cents: 990)
    create(:order, merchant:, disbursement: taken, ordered_on: Date.new(2022, 9, 1), amount_cents: 1_000, commission_cents: 10)
    create(:disbursement, merchant:, disbursed_on: Date.new(2022, 9, 5), gross_cents: 500, commission_cents: 5, net_cents: 495)
    late_arrival = create(:order, merchant:, ordered_on: Date.new(2022, 9, 1), amount_cents: 2_000, commission_cents: 20)

    described_class.call(as_of: Date.new(2022, 9, 10))

    expect(Disbursement.where(merchant:).order(:disbursed_on).pluck(:disbursed_on, :gross_cents, :net_cents)).to eq([
      [ Date.new(2022, 9, 2), 1_000, 990 ],
      [ Date.new(2022, 9, 3), 2_000, 1_980 ],
      [ Date.new(2022, 9, 5), 500, 495 ]
    ])
    expect(disbursed_on_for(late_arrival)).to eq(Date.new(2022, 9, 3))
  end

  def disbursed_on_for(order)
    Disbursement.find(order.reload.disbursement_id).disbursed_on
  end
end
