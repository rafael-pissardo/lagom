require "rails_helper"

RSpec.describe DisburseMerchantService do
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
      expect(disbursement.reference).to match(/\A[0-9a-f]{32}\z/)
      expect(disbursement.gross_cents).to eq(6_174)
      expect(disbursement.commission_cents).to eq(59)
      expect(disbursement.net_cents).to eq(6_115)
      expect(Order.includes(:disbursement).find(order.id).disbursement).to eq(disbursement)
    end

    it "locks the merchant row and sums the orders in the database before paying them" do
      merchant = create(:merchant, live_on: Date.new(2022, 9, 4), disbursement_frequency: "DAILY")
      create(:order, merchant: merchant, ordered_on: Date.new(2022, 9, 4), amount_cents: 6_174)

      queries = capture_sql { described_class.call(merchant: merchant, as_of: Date.new(2022, 9, 5)) }

      merchant_lock = queries.find { |sql| sql.include?('FROM "merchants"') && sql.include?("FOR UPDATE") }
      totals = queries.find { |sql| sql.include?('SUM("orders"."amount_cents")') && sql.include?('"disbursement_id" IS NULL') }
      insert_at = queries.index { |sql| sql.include?('INSERT INTO "disbursements"') }

      expect(merchant_lock).to include('WHERE "merchants"."id"')
      expect(queries.index(merchant_lock)).to be < insert_at
      expect(queries.index(totals)).to be < insert_at
      expect(queries.none? { |sql| sql.include?('SELECT "orders".*') }).to be true
    end

    it "pays an old order and yesterday's order in one disbursement dated the run" do
      merchant = create(:merchant, reference: "old_co", live_on: Date.new(2022, 9, 4), disbursement_frequency: "DAILY")
      old_order = create(:order, merchant: merchant, ordered_on: Date.new(2022, 9, 4), amount_cents: 1_000, commission_cents: 10)
      yesterday = create(:order, merchant: merchant, ordered_on: Date.new(2023, 11, 7), amount_cents: 2_000, commission_cents: 20)

      described_class.call(merchant: merchant, as_of: Date.new(2026, 10, 21))

      disbursement = Disbursement.find_by!(merchant: merchant, disbursed_on: Date.new(2026, 10, 21))
      expect(disbursement.net_cents).to eq(2_970)
      expect(old_order.reload.disbursement_id).to eq(disbursement.id)
      expect(yesterday.reload.disbursement_id).to eq(disbursement.id)
      expect(Disbursement.where(merchant: merchant).count).to eq(1)
    end

    it "pays every pending order in one disbursement" do
      merchant = create(:merchant, reference: "batch_co", live_on: Date.new(2022, 9, 4), disbursement_frequency: "DAILY")
      (4..8).each do |day|
        create(:order, merchant: merchant, ordered_on: Date.new(2022, 9, day), amount_cents: day * 1_000, commission_cents: day * 10)
      end

      queries = capture_sql { described_class.call(merchant: merchant, as_of: Date.new(2022, 9, 9)) }

      expect(Disbursement.where(merchant: merchant).pluck(:disbursed_on, :gross_cents)).to eq([
        [ Date.new(2022, 9, 9), 30_000 ]
      ])
      expect(merchant.orders.undisbursed.count).to eq(0)
      expect(queries.count { |sql| sql.include?('INSERT INTO "disbursements"') }).to eq(1)
      expect(queries.count { |sql| sql.include?('FROM "merchants"') && sql.include?("FOR UPDATE") }).to eq(1)
    end

    it "rolls back when fewer orders are associated than calculated" do
      merchant = create(:merchant, live_on: Date.new(2022, 9, 4), disbursement_frequency: "DAILY")
      order = create(:order, merchant: merchant, ordered_on: Date.new(2022, 9, 4), amount_cents: 6_174)
      allow_any_instance_of(ActiveRecord::Relation).to receive(:update_all).and_return(0)

      attempts = 0
      allow_any_instance_of(ActiveRecord::Relation).to receive(:update_all).and_wrap_original do |method, *args, **kwargs|
        attempts += 1
        attempts == 1 ? 0 : method.call(*args, **kwargs)
      end

      expect {
        described_class.call(merchant: merchant, as_of: Date.new(2022, 9, 5))
      }.to raise_error(DisburseMerchantService::AssociationError, "associated 0 of 1 orders")

      expect(Disbursement.count).to eq(0)
      expect(order.reload.disbursement_id).to be_nil

      described_class.call(merchant: merchant, as_of: Date.new(2022, 9, 5))

      expect(Disbursement.count).to eq(1)
      expect(order.reload.disbursement_id).to eq(Disbursement.find_by!(merchant: merchant).id)
    end

    it "does not create a disbursement when there are no eligible orders" do
      merchant = create(:merchant, live_on: Date.new(2022, 9, 4), disbursement_frequency: "DAILY")

      expect {
        described_class.call(merchant: merchant, as_of: Date.new(2022, 9, 5))
      }.not_to change(Disbursement, :count)
    end

    it "is idempotent for the same merchant and day" do
      merchant = create(:merchant, live_on: Date.new(2022, 9, 4), disbursement_frequency: "DAILY")
      order = create(:order, merchant: merchant, ordered_on: Date.new(2022, 9, 4), amount_cents: 6_174)

      described_class.call(merchant: merchant, as_of: Date.new(2022, 9, 5))
      disbursement = Disbursement.find_by!(merchant: merchant, disbursed_on: Date.new(2022, 9, 5))

      described_class.call(merchant: merchant, as_of: Date.new(2022, 9, 5))

      expect(Disbursement.where(merchant: merchant).pluck(:id, :gross_cents, :commission_cents, :net_cents)).to eq([
        [ disbursement.id, 6_174, 59, 6_115 ]
      ])
      expect(order.reload.disbursement_id).to eq(disbursement.id)
    end

    it "runs weekly merchants only on the live_on weekday and includes the pending orders" do
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

    it "pays yesterday and leaves an order placed today undisbursed" do
      merchant = create(:merchant, reference: "today_co", live_on: Date.new(2022, 9, 4), disbursement_frequency: "DAILY")
      yesterday = create(:order, merchant: merchant, ordered_on: Date.new(2022, 9, 4), amount_cents: 1_000, commission_cents: 10)
      today = create(:order, merchant: merchant, ordered_on: Date.new(2022, 9, 5), amount_cents: 2_000, commission_cents: 20)

      described_class.call(merchant: merchant, as_of: Date.new(2022, 9, 5))

      expect(yesterday.reload.disbursement_id).to eq(Disbursement.find_by!(merchant: merchant, disbursed_on: Date.new(2022, 9, 5)).id)
      expect(today.reload.disbursement_id).to be_nil
    end

    it "stores the sum of each order's commission, not the commission of the gross" do
      merchant = create(:merchant, reference: "split_co", live_on: Date.new(2022, 9, 4), disbursement_frequency: "DAILY")
      create(:order, merchant: merchant, ordered_on: Date.new(2022, 9, 4), amount_cents: 4_000, commission_cents: 40)
      create(:order, merchant: merchant, ordered_on: Date.new(2022, 9, 4), amount_cents: 4_000, commission_cents: 40)

      described_class.call(merchant: merchant, as_of: Date.new(2022, 9, 5))

      disbursement = Disbursement.find_by!(merchant: merchant)
      expect(disbursement.gross_cents).to eq(8_000)
      expect(disbursement.commission_cents).to eq(80)
      expect(disbursement.net_cents).to eq(7_920)
      expect(Commission.cents_for(8_000)).to eq(76)
    end

    it "pays two merchants on the same day under different references" do
      first = create(:merchant, reference: "first_co", live_on: Date.new(2022, 9, 4), disbursement_frequency: "DAILY")
      second = create(:merchant, reference: "second_co", live_on: Date.new(2022, 9, 4), disbursement_frequency: "DAILY")
      create(:order, merchant: first, ordered_on: Date.new(2022, 9, 4), amount_cents: 1_000, commission_cents: 10)
      create(:order, merchant: second, ordered_on: Date.new(2022, 9, 4), amount_cents: 2_000, commission_cents: 20)

      described_class.call(merchant: first, as_of: Date.new(2022, 9, 5))
      described_class.call(merchant: second, as_of: Date.new(2022, 9, 5))

      rows = Disbursement.order(:gross_cents).pluck(:reference, :disbursed_on, :gross_cents)
      expect(rows.map { |reference, disbursed_on, gross_cents| [ disbursed_on, gross_cents ] }).to eq([
        [ Date.new(2022, 9, 5), 1_000 ],
        [ Date.new(2022, 9, 5), 2_000 ]
      ])
      expect(rows.map(&:first).uniq.size).to eq(2)
    end

    it "pays a Sunday weekly merchant on the next Sunday, and skips the other weekdays" do
      merchant = create(:merchant, :weekly, reference: "sunday_co", live_on: Date.new(2022, 9, 4))
      create(:order, merchant: merchant, ordered_on: Date.new(2022, 9, 5), amount_cents: 1_000, commission_cents: 10)
      create(:order, merchant: merchant, ordered_on: Date.new(2022, 9, 10), amount_cents: 2_000, commission_cents: 20)

      described_class.call(merchant: merchant, as_of: Date.new(2022, 9, 10))
      expect(Disbursement.count).to eq(0)

      described_class.call(merchant: merchant, as_of: Date.new(2022, 9, 11))

      expect(Disbursement.where(merchant: merchant).pluck(:disbursed_on, :gross_cents, :commission_cents)).to eq([
        [ Date.new(2022, 9, 11), 3_000, 30 ]
      ])
    end

    it "pays 28 February on the leap day and 29 February on 1 March" do
      merchant = create(:merchant, reference: "leap_co", live_on: Date.new(2024, 2, 1), disbursement_frequency: "DAILY")
      create(:order, merchant: merchant, ordered_on: Date.new(2024, 2, 28), amount_cents: 1_000, commission_cents: 10)
      create(:order, merchant: merchant, ordered_on: Date.new(2024, 2, 29), amount_cents: 2_000, commission_cents: 20)

      described_class.call(merchant: merchant, as_of: Date.new(2024, 2, 29))
      described_class.call(merchant: merchant, as_of: Date.new(2024, 3, 1))

      expect(Disbursement.where(merchant: merchant).order(:disbursed_on).pluck(:disbursed_on, :gross_cents)).to eq([
        [ Date.new(2024, 2, 29), 1_000 ],
        [ Date.new(2024, 3, 1), 2_000 ]
      ])
    end

    it "waits for the next weekday when a weekly order falls at the end of the year" do
      merchant = create(:merchant, :weekly, reference: "year_week", live_on: Date.new(2022, 12, 5))
      order = create(:order, merchant: merchant, ordered_on: Date.new(2022, 12, 31), amount_cents: 1_000, commission_cents: 10)

      described_class.call(merchant: merchant, as_of: Date.new(2023, 1, 1))
      expect(Disbursement.count).to eq(0)

      described_class.call(merchant: merchant, as_of: Date.new(2023, 1, 2))

      expect(Disbursement.find_by!(merchant: merchant).disbursed_on).to eq(Date.new(2023, 1, 2))
      expect(order.reload.disbursement_id).to eq(Disbursement.find_by!(merchant: merchant).id)
    end

    it "folds skipped days into the disbursement issued on the day the job runs" do
      merchant = create(:merchant, live_on: Date.new(2022, 9, 4), disbursement_frequency: "DAILY", reference: "daily_co")
      create(:order, merchant: merchant, ordered_on: Date.new(2022, 9, 4), amount_cents: 5_000)
      create(:order, merchant: merchant, ordered_on: Date.new(2022, 9, 5), amount_cents: 6_000)

      described_class.call(merchant: merchant, as_of: Date.new(2022, 9, 7))

      expect(Disbursement.where(merchant: merchant).pluck(:disbursed_on, :gross_cents)).to eq([
        [ Date.new(2022, 9, 7), 11_000 ]
      ])
    end

    it "pays an order stored after today's disbursement on the next eligible day" do
      merchant = create(:merchant, live_on: Date.new(2022, 9, 4), disbursement_frequency: "DAILY", reference: "late_co")
      create(:order, merchant: merchant, ordered_on: Date.new(2022, 9, 4), amount_cents: 1_000, commission_cents: 10)
      described_class.call(merchant: merchant, as_of: Date.new(2022, 9, 10))
      late = create(:order, merchant: merchant, ordered_on: Date.new(2022, 9, 4), amount_cents: 2_000, commission_cents: 20)

      described_class.call(merchant: merchant, as_of: Date.new(2022, 9, 10))
      described_class.call(merchant: merchant, as_of: Date.new(2022, 9, 11))

      expect(Disbursement.where(merchant: merchant).order(:disbursed_on).pluck(:disbursed_on, :gross_cents)).to eq([
        [ Date.new(2022, 9, 10), 1_000 ],
        [ Date.new(2022, 9, 11), 2_000 ]
      ])
      expect(late.reload.disbursement_id).to eq(Disbursement.find_by!(merchant: merchant, disbursed_on: Date.new(2022, 9, 11)).id)
    end
  end

  def capture_sql
    queries = []
    callback = ->(*, payload) { queries << payload[:sql] }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
    queries
  end
end
