require "rails_helper"

RSpec.describe "Index filters", type: :request do
  let(:user) { create(:user) }

  before do
    post user_session_path, params: { user: { email: user.email, password: "password123456" } }
  end

  describe "merchants" do
    before do
      create(:merchant, reference: "padberg_group", email: "info@padberg.com", live_on: Date.new(2022, 9, 4))
      create(:merchant, :weekly, reference: "deckow_gibson", email: "info@deckow.com", live_on: Date.new(2023, 1, 10))
    end

    it "matches part of the name or email, ignoring case" do
      get merchants_path(q: "BERG")
      expect(rows).to eq([ "padberg_group" ])

      get merchants_path(q: "deckow.com")
      expect(rows).to eq([ "deckow_gibson" ])
    end

    it "matches the live since date" do
      get merchants_path(live_on: "2023-01-10")
      expect(rows).to eq([ "deckow_gibson" ])
    end

    it "matches the disbursement frequency" do
      get merchants_path(frequency: "weekly")
      expect(rows).to eq([ "deckow_gibson" ])
    end

    it "ignores a date that is not a date" do
      get merchants_path(live_on: "not-a-date")
      expect(rows).to eq([ "deckow_gibson", "padberg_group" ])
    end

    it "updates the results frame as the operator types" do
      get merchants_path

      form = page.at_css("form[action='#{merchants_path}']")
      expect(form["method"]).to eq("get")
      expect(form["data-controller"]).to eq("live-filter")
      expect(form["data-turbo-frame"]).to eq("results")
      expect(form.at_css("input[name=q]")["data-action"]).to include("input->live-filter#search")
      expect(form.at_css("input[name=live_on]")["type"]).to eq("date")
      expect(form.at_css("input[name=live_on]")["data-action"]).to include("change->live-filter#submit")
      expect(form.at_css("select[name=frequency]").css("option").map(&:text)).to eq([ "All", "DAILY", "WEEKLY" ])
      expect(page.at_css("turbo-frame#results")).to be_present
      expect(page.at_css("turbo-frame#results table")).to be_present
    end

    it "tells the operator when nothing matches the filters" do
      get merchants_path(q: "nothing-here")

      expect(page.at_css("turbo-frame#results").text).to include("No results match your filters.")
    end
  end

  describe "disbursements" do
    it "matches the merchant and the disbursement date" do
      padberg = create(:merchant, reference: "padberg_group", email: "info@padberg.com")
      deckow = create(:merchant, reference: "deckow_gibson", email: "info@deckow.com")
      create(:disbursement, merchant: padberg, disbursed_on: Date.new(2023, 1, 2), reference: "padberg_group20230102")
      create(:disbursement, merchant: deckow, disbursed_on: Date.new(2023, 1, 3), reference: "deckow_gibson20230103")

      get disbursements_path(q: "padberg")
      expect(rows).to eq([ "padberg_group20230102" ])

      get disbursements_path(disbursed_on: "2023-01-03")
      expect(rows).to eq([ "deckow_gibson20230103" ])
    end
  end

  describe "monthly fees" do
    it "matches the merchant, the month, and whether a fee was charged" do
      padberg = create(:merchant, reference: "padberg_group")
      deckow = create(:merchant, reference: "deckow_gibson")
      create(:monthly_fee, merchant: padberg, year: 2022, month: 9, charged_cents: 2_900)
      create(:monthly_fee, merchant: deckow, year: 2022, month: 10, charged_cents: 0)

      get monthly_fees_path(q: "deckow")
      expect(rows).to eq([ "deckow_gibson" ])

      get monthly_fees_path(month: "2022-09")
      expect(rows).to eq([ "padberg_group" ])

      get monthly_fees_path(charged: "zero")
      expect(rows).to eq([ "deckow_gibson" ])

      get monthly_fees_path(charged: "charged")
      expect(rows).to eq([ "padberg_group" ])
    end
  end

  describe "orders" do
    it "matches part of the order id and the order date" do
      merchant = create(:merchant, live_on: Date.new(2022, 9, 1))
      create(:order, merchant:, external_id: "a1b2c3d4e5f6", ordered_on: Date.new(2022, 9, 4))
      create(:order, merchant:, external_id: "ffffff000000", ordered_on: Date.new(2022, 9, 5))

      get merchant_orders_path(merchant, q: "B2C3")
      expect(rows).to eq([ "a1b2c3d4e5f6" ])

      get merchant_orders_path(merchant, ordered_on: "2022-09-05")
      expect(rows).to eq([ "ffffff000000" ])
    end
  end

  describe "csv imports" do
    it "matches the status, the import type, and the start date" do
      create(:csv_import, status: "failed", kind: "merchants", object_key: "merchants-failed.csv", created_at: Time.utc(2026, 1, 1, 10))
      create(:csv_import, status: "succeeded", kind: "orders", object_key: "orders-ok.csv", created_at: Time.utc(2026, 1, 2, 10))

      get csv_imports_path(status: "failed")
      expect(rows).to eq([ "failed" ])

      get csv_imports_path(kind: "orders")
      expect(rows).to eq([ "succeeded" ])

      get csv_imports_path(started_on: "2026-01-02")
      expect(rows).to eq([ "succeeded" ])
    end
  end

  def page
    Nokogiri::HTML(response.body)
  end

  def rows
    page.css("tbody tr td:first-child").map { |cell| cell.text.strip }
  end
end
