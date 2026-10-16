require "rails_helper"

RSpec.describe DisburseMerchant do
  describe ".call" do
    it "creates a daily disbursement for yesterday's undisbursed orders" do
      merchant = create(
        :merchant,
        reference: "padberg_group",
        live_on: Date.new(2022, 9, 4),
        disbursement_frequency: "DAILY"
      )
      order = create(:order, merchant: merchant, ordered_on: Date.new(2022, 9, 4), amount_cents: 6_174)

      described_class.call(merchant: merchant, as_of: Date.new(2022, 9, 5))

      disbursement = Disbursement.find_by!(merchant: merchant, disbursed_on: Date.new(2022, 9, 5))
      expect(disbursement.reference).to eq("padberg_group20220905")
      expect(disbursement.gross_cents).to eq(6_174)
      expect(disbursement.commission_cents).to eq(59)
      expect(disbursement.net_cents).to eq(6_115)
      expect(order.reload.disbursement).to eq(disbursement)
    end

    it "does not create a disbursement when there are no eligible orders" do
      merchant = create(:merchant, live_on: Date.new(2022, 9, 4), disbursement_frequency: "DAILY")

      expect {
        described_class.call(merchant: merchant, as_of: Date.new(2022, 9, 5))
      }.not_to change(Disbursement, :count)
    end

    it "is idempotent for the same merchant and day" do
      merchant = create(:merchant, live_on: Date.new(2022, 9, 4), disbursement_frequency: "DAILY")
      create(:order, merchant: merchant, ordered_on: Date.new(2022, 9, 4), amount_cents: 6_174)

      described_class.call(merchant: merchant, as_of: Date.new(2022, 9, 5))

      expect {
        described_class.call(merchant: merchant, as_of: Date.new(2022, 9, 5))
      }.not_to change(Disbursement, :count)
    end

    it "runs weekly merchants only on the live_on weekday and catches up missed days" do
      live_on = Date.new(2022, 9, 5) # Monday
      merchant = create(:merchant, live_on: live_on, disbursement_frequency: "WEEKLY", reference: "weekly_co")
      create(:order, merchant: merchant, ordered_on: Date.new(2022, 9, 6), amount_cents: 10_000)
      create(:order, merchant: merchant, ordered_on: Date.new(2022, 9, 10), amount_cents: 20_000)

      described_class.call(merchant: merchant, as_of: Date.new(2022, 9, 7))
      expect(Disbursement.count).to eq(0)

      described_class.call(merchant: merchant, as_of: Date.new(2022, 9, 12))

      disbursement = Disbursement.find_by!(merchant: merchant, disbursed_on: Date.new(2022, 9, 12))
      expect(disbursement.gross_cents).to eq(30_000)
      expect(merchant.orders.undisbursed.count).to eq(0)
    end

    it "includes overdue orders when a previous day was missed" do
      merchant = create(:merchant, live_on: Date.new(2022, 9, 4), disbursement_frequency: "DAILY", reference: "daily_co")
      create(:order, merchant: merchant, ordered_on: Date.new(2022, 9, 4), amount_cents: 5_000)
      create(:order, merchant: merchant, ordered_on: Date.new(2022, 9, 5), amount_cents: 6_000)

      described_class.call(merchant: merchant, as_of: Date.new(2022, 9, 7))

      disbursement = Disbursement.find_by!(merchant: merchant, disbursed_on: Date.new(2022, 9, 7))
      expect(disbursement.gross_cents).to eq(11_000)
    end
  end
end
