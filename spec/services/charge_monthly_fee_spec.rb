require "rails_helper"

RSpec.describe ChargeMonthlyFee do
  describe ".call" do
    it "charges the remaining amount when commissions are below the minimum" do
      merchant = create(:merchant, live_on: Date.new(2022, 9, 1), minimum_monthly_fee_cents: 2_900)
      create(:order, merchant: merchant, ordered_on: Date.new(2022, 9, 10), amount_cents: 5_000)

      described_class.call(merchant: merchant, year: 2022, month: 9)

      fee = MonthlyFee.find_by!(merchant: merchant, year: 2022, month: 9)
      expect(fee.commissions_cents).to eq(48)
      expect(fee.charged_cents).to eq(2_852)
    end

    it "stores a zero charge when commissions meet the minimum" do
      merchant = create(:merchant, live_on: Date.new(2022, 9, 1), minimum_monthly_fee_cents: 48)
      create(:order, merchant: merchant, ordered_on: Date.new(2022, 9, 10), amount_cents: 5_000)

      described_class.call(merchant: merchant, year: 2022, month: 9)

      fee = MonthlyFee.find_by!(merchant: merchant, year: 2022, month: 9)
      expect(fee.commissions_cents).to eq(48)
      expect(fee.charged_cents).to eq(0)
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

    it "skips months before the merchant live_on month" do
      merchant = create(:merchant, live_on: Date.new(2022, 10, 15), minimum_monthly_fee_cents: 2_900)

      expect {
        described_class.call(merchant: merchant, year: 2022, month: 9)
      }.not_to change(MonthlyFee, :count)
    end
  end
end
