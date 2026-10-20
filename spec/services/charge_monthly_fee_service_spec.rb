require "rails_helper"

RSpec.describe ChargeMonthlyFeeService do
  describe ".call" do
    it "charges the remaining amount when commissions are below the minimum" do
      merchant = create(:merchant, live_on: Date.new(2022, 9, 1), minimum_monthly_fee_cents: 2_900)
      create(:order, merchant: merchant, ordered_on: Date.new(2022, 9, 10), amount_cents: 5_000)

      described_class.call(merchant: merchant, year: 2022, month: 9)

      fee = MonthlyFee.find_by!(merchant: merchant, year: 2022, month: 9)
      expect(fee.commissions_cents).to eq(48)
      expect(fee.charged_cents).to eq(2_852)
    end

    it "stores a zero charge when commissions meet or pass the minimum, and when the minimum is zero" do
      meeting = create(:merchant, reference: "meeting", live_on: Date.new(2022, 9, 1), minimum_monthly_fee_cents: 48)
      passing = create(:merchant, reference: "passing", live_on: Date.new(2022, 9, 1), minimum_monthly_fee_cents: 1)
      zero = create(:merchant, reference: "zero_min", live_on: Date.new(2022, 9, 1), minimum_monthly_fee_cents: 0)
      create(:order, merchant: meeting, ordered_on: Date.new(2022, 9, 10), amount_cents: 5_000)
      create(:order, merchant: passing, ordered_on: Date.new(2022, 9, 10), amount_cents: 5_000)

      described_class.call(merchant: meeting, year: 2022, month: 9)
      described_class.call(merchant: passing, year: 2022, month: 9)
      described_class.call(merchant: zero, year: 2022, month: 9)

      expect(MonthlyFee.find_by!(merchant: meeting, year: 2022, month: 9).charged_cents).to eq(0)
      expect(MonthlyFee.find_by!(merchant: passing, year: 2022, month: 9)).to have_attributes(commissions_cents: 48, charged_cents: 0)
      expect(MonthlyFee.find_by!(merchant: zero, year: 2022, month: 9)).to have_attributes(commissions_cents: 0, charged_cents: 0)
    end

    it "charges the full minimum when the month has no commissions" do
      merchant = create(:merchant, live_on: Date.new(2022, 9, 1), minimum_monthly_fee_cents: 2_900)

      described_class.call(merchant: merchant, year: 2022, month: 9)

      fee = MonthlyFee.find_by!(merchant: merchant, year: 2022, month: 9)
      expect(fee.commissions_cents).to eq(0)
      expect(fee.charged_cents).to eq(2_900)
    end

    it "is idempotent for the same merchant and month" do
      merchant = create(:merchant, live_on: Date.new(2022, 9, 1), minimum_monthly_fee_cents: 2_900)

      described_class.call(merchant: merchant, year: 2022, month: 9)

      expect {
        described_class.call(merchant: merchant, year: 2022, month: 9)
      }.not_to change(MonthlyFee, :count)
    end

    it "charges the full minimum for the live_on month, including a start on the last day" do
      mid_month = create(:merchant, reference: "mid_month", live_on: Date.new(2022, 10, 15), minimum_monthly_fee_cents: 100)
      last_day = create(:merchant, reference: "last_day", live_on: Date.new(2022, 10, 31), minimum_monthly_fee_cents: 250)

      described_class.call(merchant: mid_month, year: 2022, month: 10)
      described_class.call(merchant: last_day, year: 2022, month: 10)

      expect(MonthlyFee.find_by!(merchant: mid_month, year: 2022, month: 10).charged_cents).to eq(100)
      expect(MonthlyFee.find_by!(merchant: last_day, year: 2022, month: 10).charged_cents).to eq(250)
    end

    it "charges the full minimum when the month's orders have zero commission" do
      merchant = create(:merchant, live_on: Date.new(2022, 9, 1), minimum_monthly_fee_cents: 100)
      create(:order, merchant: merchant, ordered_on: Date.new(2022, 9, 10), amount_cents: 0, commission_cents: 0)

      described_class.call(merchant: merchant, year: 2022, month: 9)

      fee = MonthlyFee.find_by!(merchant: merchant, year: 2022, month: 9)
      expect(fee.commissions_cents).to eq(0)
      expect(fee.charged_cents).to eq(100)
    end

    it "skips months before the merchant live_on month" do
      merchant = create(:merchant, live_on: Date.new(2022, 10, 15), minimum_monthly_fee_cents: 2_900)

      expect {
        described_class.call(merchant: merchant, year: 2022, month: 9)
      }.not_to change(MonthlyFee, :count)
    end
  end
end
