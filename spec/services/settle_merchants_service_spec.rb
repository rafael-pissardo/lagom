require "rails_helper"

RSpec.describe SettleMerchantsService do
  it "disburses eligible daily merchants and charges their monthly fee on the first day" do
    merchant = create(:merchant, reference: "daily_settle", live_on: Date.new(2022, 9, 1), disbursement_frequency: "DAILY", minimum_monthly_fee_cents: 100)
    create(:order, merchant: merchant, ordered_on: Date.new(2022, 9, 30), amount_cents: 5_000)

    described_class.call(frequency: "DAILY", as_of: Date.new(2022, 10, 1))

    expect(Disbursement.find_by(merchant: merchant, disbursed_on: Date.new(2022, 10, 1))).to be_present
    fee = MonthlyFee.find_by!(merchant: merchant, year: 2022, month: 9)
    expect(fee.charged_cents).to eq(52)
  end

  it "charges the previous month when the first successful run is the 2nd" do
    merchant = create(:merchant, reference: "fee_day_two", live_on: Date.new(2022, 9, 1), disbursement_frequency: "DAILY", minimum_monthly_fee_cents: 100)
    create(:order, merchant:, ordered_on: Date.new(2022, 9, 30), amount_cents: 5_000)

    described_class.call(frequency: "DAILY", as_of: Date.new(2022, 10, 2))

    fee = MonthlyFee.find_by!(merchant:, year: 2022, month: 9)
    expect(fee.charged_cents).to eq(52)

    expect { described_class.call(frequency: "DAILY", as_of: Date.new(2022, 10, 2)) }.not_to change(MonthlyFee, :count)
  end

  it "creates one disbursement per missed day, with its own reference and total" do
    merchant = create(:merchant, reference: "gap_daily", live_on: Date.new(2022, 9, 1), disbursement_frequency: "DAILY", minimum_monthly_fee_cents: 0)
    create(:order, merchant:, ordered_on: Date.new(2022, 9, 1), amount_cents: 1_000, commission_cents: 10)
    create(:order, merchant:, ordered_on: Date.new(2022, 9, 2), amount_cents: 2_000, commission_cents: 20)
    create(:order, merchant:, ordered_on: Date.new(2022, 9, 3), amount_cents: 3_000, commission_cents: 30)
    create(:order, merchant:, ordered_on: Date.new(2022, 9, 4), amount_cents: 4_000, commission_cents: 40)

    described_class.call(frequency: "DAILY", as_of: Date.new(2022, 9, 2))
    described_class.call(frequency: "DAILY", as_of: Date.new(2022, 9, 5))

    rows = Disbursement.where(merchant: merchant).order(:disbursed_on).pluck(:reference, :net_cents)
    expect(rows.map(&:last)).to eq([ 990, 1_980, 2_970, 3_960 ])
    expect(rows.map(&:first).uniq.size).to eq(4)
    expect(rows.map(&:first)).to all(match(/\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/))
    expect(Order.where(merchant: merchant).distinct.pluck(:disbursement_id).size).to eq(4)
  end

  it "catches up a weekly merchant only on the live_on weekday" do
    merchant = create(:merchant, :weekly, reference: "gap_weekly", live_on: Date.new(2022, 9, 7), minimum_monthly_fee_cents: 0)
    create(:order, merchant:, ordered_on: Date.new(2022, 9, 7), amount_cents: 1_000, commission_cents: 10)

    described_class.call(frequency: "WEEKLY", as_of: Date.new(2022, 9, 16))

    expect(Disbursement.where(merchant: merchant).pluck(:disbursed_on, :net_cents)).to eq([ [ Date.new(2022, 9, 14), 990 ] ])
  end

  it "settles only the merchants of that frequency" do
    daily = create(:merchant, reference: "daily_only", live_on: Date.new(2022, 9, 1), disbursement_frequency: "DAILY", minimum_monthly_fee_cents: 100)
    weekly = create(:merchant, :weekly, reference: "weekly_only", live_on: Date.new(2022, 9, 1), minimum_monthly_fee_cents: 100)
    create(:order, merchant: daily, ordered_on: Date.new(2022, 9, 30), amount_cents: 5_000, commission_cents: 48)
    create(:order, merchant: weekly, ordered_on: Date.new(2022, 9, 30), amount_cents: 5_000, commission_cents: 48)

    described_class.call(frequency: "DAILY", as_of: Date.new(2022, 10, 1))

    expect(Disbursement.where(merchant: daily).pluck(:disbursed_on)).to eq([ Date.new(2022, 10, 1) ])
    expect(MonthlyFee.where(merchant: daily, year: 2022, month: 9).pluck(:charged_cents)).to eq([ 52 ])
    expect(Disbursement.where(merchant: weekly)).to be_empty
    expect(MonthlyFee.where(merchant: weekly)).to be_empty

    described_class.call(frequency: "WEEKLY", as_of: Date.new(2022, 10, 1))

    expect(Disbursement.where(merchant: daily).count).to eq(1)
    expect(MonthlyFee.where(merchant: weekly, year: 2022, month: 9).pluck(:charged_cents)).to eq([ 52 ])
    expect(Disbursement.where(merchant: weekly)).to be_empty
  end

  it "disburses 2022 and 2023 orders on a 2026 run and charges every month since live_on" do
    merchant = create(:merchant, reference: "late_2022", live_on: Date.new(2022, 9, 1), disbursement_frequency: "DAILY", minimum_monthly_fee_cents: 2_900)
    create(:order, merchant:, ordered_on: Date.new(2022, 9, 15), amount_cents: 5_000, commission_cents: 48)
    create(:order, merchant:, ordered_on: Date.new(2023, 11, 7), amount_cents: 10_000, commission_cents: 100)

    described_class.call(frequency: "DAILY", as_of: Date.new(2026, 10, 21))

    expect(Disbursement.where(merchant:).order(:disbursed_on).pluck(:disbursed_on, :gross_cents)).to eq([
      [ Date.new(2022, 9, 16), 5_000 ],
      [ Date.new(2023, 11, 8), 10_000 ]
    ])
    months = (Date.new(2022, 9, 1)..Date.new(2026, 9, 1)).select { |day| day.day == 1 }.map { |day| [ day.year, day.month ] }
    expect(MonthlyFee.where(merchant:).order(:year, :month).pluck(:year, :month)).to eq(months)
    expect(MonthlyFee.find_by!(merchant:, year: 2022, month: 9)).to have_attributes(commissions_cents: 48, charged_cents: 2_852)
    expect(MonthlyFee.find_by!(merchant:, year: 2022, month: 10)).to have_attributes(commissions_cents: 0, charged_cents: 2_900)
    expect(MonthlyFee.find_by!(merchant:, year: 2023, month: 11)).to have_attributes(commissions_cents: 100, charged_cents: 2_800)
    expect(MonthlyFee.find_by!(merchant:, year: 2026, month: 9)).to have_attributes(commissions_cents: 0, charged_cents: 2_900)
    expect(MonthlyFee.exists?(merchant:, year: 2026, month: 10)).to be(false)

    expect { described_class.call(frequency: "DAILY", as_of: Date.new(2026, 10, 21)) }.not_to change(MonthlyFee, :count)
  end

  it "credits a charged month when a later import adds orders to it, without touching the fee row" do
    merchant = create(:merchant, reference: "late_fee", live_on: Date.new(2022, 9, 1), disbursement_frequency: "DAILY", minimum_monthly_fee_cents: 2_900)
    described_class.call(frequency: "DAILY", as_of: Date.new(2022, 10, 1))
    fee = MonthlyFee.find_by!(merchant:, year: 2022, month: 9)
    create(:order, merchant:, ordered_on: Date.new(2022, 9, 15), amount_cents: 5_000)

    described_class.call(frequency: "DAILY", as_of: Date.new(2022, 10, 2))

    expect(fee.reload).to have_attributes(commissions_cents: 0, charged_cents: 2_900)
    expect(MonthlyFeeAdjustment.where(monthly_fee: fee).pluck(:commissions_cents, :credit_cents)).to eq([ [ 48, 48 ] ])
    expect(Disbursement.where(merchant:).pluck(:disbursed_on, :gross_cents)).to eq([ [ Date.new(2022, 9, 16), 5_000 ] ])
  end

  it "does not create a second disbursement or monthly fee for a day it already settled" do
    merchant = create(:merchant, reference: "same_day", live_on: Date.new(2022, 9, 1), disbursement_frequency: "DAILY", minimum_monthly_fee_cents: 100)
    order = create(:order, merchant:, ordered_on: Date.new(2022, 9, 30), amount_cents: 5_000, commission_cents: 48)

    described_class.call(frequency: "DAILY", as_of: Date.new(2022, 10, 1))
    disbursement = Disbursement.find_by!(merchant:, disbursed_on: Date.new(2022, 10, 1))
    fee = MonthlyFee.find_by!(merchant:, year: 2022, month: 9)

    described_class.call(frequency: "DAILY", as_of: Date.new(2022, 10, 1))

    expect(Disbursement.where(merchant:).order(:disbursed_on).pluck(:id, :disbursed_on, :gross_cents, :commission_cents, :net_cents)).to eq([
      [ disbursement.id, Date.new(2022, 10, 1), disbursement.gross_cents, disbursement.commission_cents, disbursement.net_cents ]
    ])
    expect(MonthlyFee.where(merchant:).pluck(:id, :year, :month, :commissions_cents, :charged_cents)).to eq([
      [ fee.id, 2022, 9, fee.commissions_cents, fee.charged_cents ]
    ])
    expect(order.reload.disbursement_id).to eq(disbursement.id)
  end
end
