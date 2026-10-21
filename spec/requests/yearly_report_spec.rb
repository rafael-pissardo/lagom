require "rails_helper"

RSpec.describe "Yearly report", type: :request do
  let(:user) { create(:user) }
  let(:merchant) { create(:merchant, reference: "report_page", live_on: Date.new(2010, 1, 1)) }

  before do
    post user_session_path, params: { user: { email: user.email, password: "password123456" } }
  end

  it "pages ten years and keeps the default year order" do
    (2010..2020).each do |year|
      create(:disbursement, merchant:, disbursed_on: Date.new(year, 6, 1), net_cents: year, gross_cents: year, commission_cents: 0)
    end

    get reports_yearly_path

    expect(rows).to eq((2010..2019).map(&:to_s))
    expect(response.body).not_to include(">2020<")
    expect(summary).to eq("Showing 1–10 of 11 · 10 per page")
    expect(response.body).to include("page=2")
    expect(active_sort).to eq("year-asc")
    expect(directions("Year")).to eq(%w[↑ ↓])
    expect(sort_link("year", "desc")["data-turbo-frame"]).to eq("results")
    expect(response.body).to include(Turbo::StreamsChannel.signed_stream_name("yearly_report"))

    get reports_yearly_path(page: 2)

    expect(rows).to eq(%w[2020])
    expect(summary).to eq("Showing 11 of 11 · 10 per page")
  end

  it "filters by part of the year and sorts the columns" do
    create(:disbursement, merchant:, disbursed_on: Date.new(2022, 6, 1), reference: "one", gross_cents: 100, commission_cents: 10, net_cents: 90)
    create(:disbursement, merchant:, disbursed_on: Date.new(2022, 6, 2), reference: "two", gross_cents: 100, commission_cents: 10, net_cents: 90)
    create(:disbursement, merchant:, disbursed_on: Date.new(2023, 6, 1), reference: "three", gross_cents: 500, commission_cents: 40, net_cents: 460)
    fee = create(:monthly_fee, merchant:, year: 2023, month: 6, commissions_cents: 40, charged_cents: 20)
    travel_to(Time.zone.local(2023, 6, 15)) do
      create(:monthly_fee_adjustment, monthly_fee: fee, commissions_cents: 40, credit_cents: 15)
    end

    get reports_yearly_path(year: "2022")
    expect(rows).to eq(%w[2022])

    get reports_yearly_path(year: "1999")
    expect(page.at_css("turbo-frame#results").text).to include("No results match your filters.")

    get reports_yearly_path
    form = page.at_css("form[role=search]")
    expect(form["data-controller"]).to eq("live-filter")
    expect(form["data-turbo-frame"]).to eq("results")
    expect(form.at_css("input[name=year]")["data-action"]).to include("input->live-filter#search")

    get reports_yearly_path(sort: "disbursements", direction: "desc")
    expect(rows).to eq(%w[2022 2023])

    get reports_yearly_path(sort: "amount_disbursed", direction: "asc")
    expect(rows).to eq(%w[2022 2023])

    get reports_yearly_path(sort: "monthly_fees_count", direction: "desc")
    expect(rows).to eq(%w[2023 2022])
    expect(report("competence").text).to include("0.20 €")
    expect(report("competence").text).not_to include("0.15 €")
    expect(header("Amount of monthly fees")).to be_present
    expect(header("Total without adjustments")).to be_nil
    expect(report("adjustments").text).to include("Charged year").and include("Reference year").and include("0.15 €")

    get reports_yearly_path(sort: "monthly_fees_amount", direction: "desc")
    expect(rows).to eq(%w[2023 2022])

    get reports_yearly_path(sort: "amount_disbursed", direction: "nope")
    expect(rows).to eq(%w[2022 2023])

    get reports_yearly_path(sort: "drop table", direction: "desc")
    expect(rows).to eq(%w[2022 2023])
  end

  it "keeps the sort when the year filter is submitted" do
    create(:disbursement, merchant:, disbursed_on: Date.new(2022, 6, 1))

    get reports_yearly_path(year: "202", sort: "year", direction: "desc")

    form = page.at_css("form[role=search]")
    expect(form.at_css("input[name=sort]")["value"]).to eq("year")
    expect(form.at_css("input[name=direction]")["value"]).to eq("desc")
    expect(sort_link("order_fees", "asc")["href"]).to include("year=202").and include("sort=order_fees")
    expect(sort_link("order_fees", "asc")["href"]).not_to include("page=")
  end

  def page
    Nokogiri::HTML(response.body)
  end

  def rows
    report("competence").css("tbody tr").map { |row| row.at_css("td").text.strip }
  end

  def report(name)
    page.at_css(%([data-report="#{name}"]))
  end

  def summary
    page.at_css("[data-testid=pagination-summary]").text.gsub(/\s+/, " ").strip
  end

  def directions(label)
    header(label).css("a").map { |link| link.text.strip }
  end

  def active_sort
    link = page.at_css('thead a[aria-current="true"]')
    "#{link["data-sort"]}-#{link["data-direction"]}"
  end

  def sort_link(column, direction)
    page.at_css(%(thead a[data-sort="#{column}"][data-direction="#{direction}"]))
  end

  def header(label)
    page.css("thead th").find { |cell| cell.at_css("[data-sort-label]")&.text&.strip == label }
  end
end
