require "rails_helper"

RSpec.describe AdjustMonthlyFeesService do
  it "credits the difference when late orders raise the commissions of a charged month, and keeps the charge" do
    merchant = create(:merchant, live_on: Date.new(2022, 9, 1), minimum_monthly_fee_cents: 2_900)
    fee = create(:monthly_fee, merchant: merchant, year: 2022, month: 9, commissions_cents: 48, charged_cents: 2_852)
    create(:order, merchant: merchant, ordered_on: Date.new(2022, 9, 10), amount_cents: 5_000)
    create(:order, merchant: merchant, ordered_on: Date.new(2022, 9, 20), amount_cents: 5_000)

    described_class.call(merchant: merchant)

    expect(fee.reload).to have_attributes(commissions_cents: 48, charged_cents: 2_852)
    expect(MonthlyFeeAdjustment.where(monthly_fee: fee).pluck(:commissions_cents, :credit_cents)).to eq([ [ 96, 48 ] ])
  end

  it "does not record a second adjustment when nothing changed" do
    merchant = create(:merchant, live_on: Date.new(2022, 9, 1), minimum_monthly_fee_cents: 2_900)
    fee = create(:monthly_fee, merchant: merchant, year: 2022, month: 9, commissions_cents: 0, charged_cents: 2_900)
    create(:order, merchant: merchant, ordered_on: Date.new(2022, 9, 10), amount_cents: 5_000)

    described_class.call(merchant: merchant)
    adjustment = MonthlyFeeAdjustment.find_by!(monthly_fee: fee)

    expect { described_class.call(merchant: merchant) }.not_to change(MonthlyFeeAdjustment, :count)
    expect(MonthlyFeeAdjustment.where(monthly_fee: fee).pluck(:id, :credit_cents)).to eq([ [ adjustment.id, 48 ] ])
  end

  it "credits later orders in a fee's own month after a carried credit, and keeps the fee" do
    merchant = create(:merchant, live_on: Date.new(2022, 9, 1), minimum_monthly_fee_cents: 2_900)
    fee = create(:monthly_fee, merchant: merchant, year: 2026, month: 9, commissions_cents: 0, charged_cents: 2_852)
    create(:monthly_fee_adjustment, monthly_fee: fee, commissions_cents: 48, credit_cents: 48, carried: true)
    create(:order, merchant: merchant, ordered_on: Date.new(2026, 9, 10), amount_cents: 1_000, commission_cents: 10)

    described_class.call(merchant: merchant)

    expect(fee.reload.charged_cents).to eq(2_852)
    expect(MonthlyFeeAdjustment.where(monthly_fee: fee, carried: false).pluck(:commissions_cents, :credit_cents)).to eq([ [ 10, 10 ] ])
  end

  it "credits only the further difference when more late orders arrive" do
    merchant = create(:merchant, live_on: Date.new(2022, 9, 1), minimum_monthly_fee_cents: 2_900)
    fee = create(:monthly_fee, merchant: merchant, year: 2022, month: 9, commissions_cents: 0, charged_cents: 2_900)
    create(:order, merchant: merchant, ordered_on: Date.new(2022, 9, 10), amount_cents: 5_000)
    described_class.call(merchant: merchant)
    create(:order, merchant: merchant, ordered_on: Date.new(2022, 9, 11), amount_cents: 1_000, commission_cents: 10)

    described_class.call(merchant: merchant)

    expect(MonthlyFeeAdjustment.where(monthly_fee: fee).order(:created_at).pluck(:commissions_cents, :credit_cents)).to eq([
      [ 48, 48 ],
      [ 58, 10 ]
    ])
  end

  it "never credits more than what was charged" do
    merchant = create(:merchant, live_on: Date.new(2022, 9, 1), minimum_monthly_fee_cents: 100)
    fee = create(:monthly_fee, merchant: merchant, year: 2022, month: 9, commissions_cents: 0, charged_cents: 100)
    create(:order, merchant: merchant, ordered_on: Date.new(2022, 9, 10), amount_cents: 20_000, commission_cents: 190)
    described_class.call(merchant: merchant)
    create(:order, merchant: merchant, ordered_on: Date.new(2022, 9, 12), amount_cents: 1_000, commission_cents: 10)

    described_class.call(merchant: merchant)

    expect(MonthlyFeeAdjustment.where(monthly_fee: fee).order(:created_at).pluck(:commissions_cents, :credit_cents)).to eq([
      [ 190, 100 ],
      [ 200, 0 ]
    ])
  end

  it "leaves the fee alone when the month was charged with its current commissions" do
    merchant = create(:merchant, live_on: Date.new(2022, 9, 1), minimum_monthly_fee_cents: 2_900)
    create(:order, merchant: merchant, ordered_on: Date.new(2022, 9, 10), amount_cents: 5_000)
    create(:monthly_fee, merchant: merchant, year: 2022, month: 9, commissions_cents: 48, charged_cents: 2_852)

    expect { described_class.call(merchant: merchant) }.not_to change(MonthlyFeeAdjustment, :count)
  end

  it "touches only the months of that merchant" do
    merchant = create(:merchant, reference: "mine", live_on: Date.new(2022, 9, 1), minimum_monthly_fee_cents: 2_900)
    other = create(:merchant, reference: "other", live_on: Date.new(2022, 9, 1), minimum_monthly_fee_cents: 2_900)
    create(:monthly_fee, merchant: merchant, year: 2022, month: 9, commissions_cents: 0, charged_cents: 2_900)
    other_fee = create(:monthly_fee, merchant: other, year: 2022, month: 9, commissions_cents: 0, charged_cents: 2_900)
    create(:order, merchant: other, ordered_on: Date.new(2022, 9, 10), amount_cents: 5_000)

    described_class.call(merchant: merchant)

    expect(MonthlyFeeAdjustment.count).to eq(0)
    expect(other_fee.reload.charged_cents).to eq(2_900)
  end
end
