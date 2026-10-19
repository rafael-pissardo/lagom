require "rails_helper"

RSpec.describe "Index sorting", type: :request do
  let(:user) { create(:user) }

  before do
    post user_session_path, params: { user: { email: user.email, password: "password123456" } }
  end

  it "sorts merchants by each column, ascending and descending" do
    create(:merchant, reference: "zeta", email: "a@zeta.com", live_on: Date.new(2024, 2, 1), minimum_monthly_fee_cents: 100)
    create(:merchant, :weekly, reference: "alpha", email: "b@alpha.com", live_on: Date.new(2022, 3, 1), minimum_monthly_fee_cents: 9_000)

    get merchants_path
    expect(rows).to eq(%w[alpha zeta])
    expect(directions("Merchant")).to eq(%w[ASC DESC])
    expect(active_sort).to eq("reference-asc")
    expect(sort_link("reference", "desc")["data-turbo-frame"]).to eq("results")

    get merchants_path(sort: "reference", direction: "desc")
    expect(rows).to eq(%w[zeta alpha])
    expect(active_sort).to eq("reference-desc")

    get merchants_path(sort: "email", direction: "asc")
    expect(rows).to eq(%w[zeta alpha])

    get merchants_path(sort: "live_on", direction: "desc")
    expect(rows).to eq(%w[zeta alpha])

    get merchants_path(sort: "frequency", direction: "asc")
    expect(rows).to eq(%w[zeta alpha])

    get merchants_path(sort: "fee", direction: "desc")
    expect(rows).to eq(%w[alpha zeta])

    get merchants_path(sort: "fee", direction: "nope")
    expect(rows).to eq(%w[zeta alpha])

    get merchants_path(sort: "drop table", direction: "desc")
    expect(rows).to eq(%w[alpha zeta])
  end

  it "keeps the sort when the filter is submitted" do
    create(:merchant, reference: "alpha")
    create(:merchant, reference: "beta")

    get merchants_path(q: "a", sort: "reference", direction: "desc")

    form = Nokogiri::HTML(response.body).at_css("form[role=search]")
    expect(form.at_css("input[name=sort]")["value"]).to eq("reference")
    expect(form.at_css("input[name=direction]")["value"]).to eq("desc")
    expect(sort_link("email", "asc")["href"]).to include("q=a").and include("sort=email").and include("direction=asc")
    expect(sort_link("email", "asc")["href"]).not_to include("page=")
  end

  it "sorts disbursements by amount and date" do
    merchant = create(:merchant, reference: "sorted")
    create(:disbursement, merchant:, disbursed_on: Date.new(2022, 9, 5), reference: "small", gross_cents: 100, commission_cents: 10, net_cents: 90)
    create(:disbursement, merchant:, disbursed_on: Date.new(2022, 9, 6), reference: "large", gross_cents: 500, commission_cents: 10, net_cents: 490)

    get disbursements_path
    expect(rows).to eq(%w[large small])

    get disbursements_path(sort: "gross", direction: "asc")
    expect(rows).to eq(%w[small large])

    get disbursements_path(sort: "disbursed_on", direction: "asc")
    expect(rows).to eq(%w[small large])
  end

  it "sorts orders by id and amount" do
    merchant = create(:merchant, reference: "orders_sort", live_on: Date.new(2022, 1, 1))
    create(:order, merchant:, external_id: "bbbbbbbbbbbb", ordered_on: Date.new(2022, 1, 2), amount_cents: 100, commission_cents: 1)
    create(:order, merchant:, external_id: "aaaaaaaaaaaa", ordered_on: Date.new(2022, 1, 3), amount_cents: 900, commission_cents: 9)

    get merchant_orders_path(merchant)
    expect(rows).to eq(%w[aaaaaaaaaaaa bbbbbbbbbbbb])

    get merchant_orders_path(merchant, sort: "external_id", direction: "desc")
    expect(rows).to eq(%w[bbbbbbbbbbbb aaaaaaaaaaaa])

    get merchant_orders_path(merchant, sort: "amount", direction: "asc")
    expect(rows).to eq(%w[bbbbbbbbbbbb aaaaaaaaaaaa])
  end

  it "sorts monthly fees by merchant and charged amount" do
    alpha = create(:merchant, reference: "alpha")
    zeta = create(:merchant, reference: "zeta")
    create(:monthly_fee, merchant: zeta, year: 2022, month: 1, commissions_cents: 10, charged_cents: 0)
    create(:monthly_fee, merchant: alpha, year: 2023, month: 5, commissions_cents: 80, charged_cents: 20)

    get monthly_fees_path
    expect(rows).to eq(%w[alpha zeta])

    get monthly_fees_path(sort: "merchant", direction: "desc")
    expect(rows).to eq(%w[zeta alpha])

    get monthly_fees_path(sort: "charged", direction: "asc")
    expect(rows).to eq(%w[zeta alpha])
  end

  it "sorts csv imports by status and rows imported" do
    create(:csv_import, object_key: "later.csv", status: "failed", kind: "orders", imported_count: 1, failed_count: 4, created_at: Time.utc(2026, 1, 2))
    create(:csv_import, object_key: "earlier.csv", status: "pending", kind: "merchants", imported_count: 9, failed_count: 0, created_at: Time.utc(2026, 1, 1))

    get csv_imports_path
    expect(rows).to eq(%w[failed pending])

    get csv_imports_path(sort: "status", direction: "desc")
    expect(rows).to eq(%w[pending failed])

    get csv_imports_path(sort: "imported", direction: "asc")
    expect(rows).to eq(%w[failed pending])
  end

  def rows
    Nokogiri::HTML(response.body).css("tbody tr").map { |row| row.at_css("td").text.strip }
  end

  def directions(label)
    header(label).css("a").map { |link| link.text.strip }
  end

  def active_sort
    link = Nokogiri::HTML(response.body).at_css('thead a[aria-current="true"]')
    "#{link["data-sort"]}-#{link["data-direction"]}"
  end

  def sort_link(column, direction)
    Nokogiri::HTML(response.body).at_css(%(thead a[data-sort="#{column}"][data-direction="#{direction}"]))
  end

  def header(label)
    Nokogiri::HTML(response.body).css("thead th").find { |cell| cell.at_css("[data-sort-label]")&.text&.strip == label }
  end
end
