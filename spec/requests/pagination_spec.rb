require "rails_helper"

RSpec.describe "Index pagination", type: :request do
  let(:user) { create(:user) }

  before do
    post user_session_path, params: { user: { email: user.email, password: "password123456" } }
  end

  it "shows 10 merchants per page" do
    11.times { |n| create(:merchant, reference: format("page-%02d", n)) }

    get merchants_path

    expect(table_rows).to eq(10)
    expect(response.body).to include("page-00")
    expect(response.body).not_to include("page-10")
    expect(response.body).to include("page=2")

    get merchants_path(page: 2)

    expect(table_rows).to eq(1)
    expect(response.body).to include("page-10")
    expect(response.body).not_to include("page-00")
  end

  it "shows 10 orders per page" do
    merchant = create(:merchant, reference: "orders_page", live_on: Date.new(2022, 1, 1))
    11.times do |n|
      create(:order, merchant:, ordered_on: Date.new(2022, 1, 1) + n, external_id: format("order-%02d", n))
    end

    get merchant_orders_path(merchant)

    expect(table_rows).to eq(10)
    expect(response.body).to include("order-10")
    expect(response.body).not_to include("order-00")

    get merchant_orders_path(merchant, page: 2)

    expect(table_rows).to eq(1)
    expect(response.body).to include("order-00")
  end

  it "shows 10 disbursements per page" do
    merchant = create(:merchant, reference: "disb_page")
    11.times do |n|
      create(:disbursement, merchant:, disbursed_on: Date.new(2022, 9, 5) + n, reference: format("disb-%02d", n))
    end

    get disbursements_path

    expect(table_rows).to eq(10)
    expect(response.body).to include("disb-10")
    expect(response.body).not_to include("disb-00")

    get disbursements_path(page: 2)

    expect(table_rows).to eq(1)
    expect(response.body).to include("disb-00")
  end

  it "shows 10 monthly fees per page" do
    merchant = create(:merchant, reference: "fee_page")
    11.times { |n| create(:monthly_fee, merchant:, year: 2022, month: n + 1) }

    get monthly_fees_path

    expect(table_rows).to eq(10)

    get monthly_fees_path(page: 2)

    expect(table_rows).to eq(1)
  end

  it "shows 10 csv imports per page" do
    11.times do |n|
      create(:csv_import, object_key: format("page-%02d.csv", n), created_at: Time.utc(2026, 1, 1, n))
    end

    get csv_imports_path

    expect(table_rows).to eq(10)

    get csv_imports_path(page: 2)

    expect(table_rows).to eq(1)
  end

  it "hides the pager when the page is not full" do
    create(:merchant, reference: "only_one")

    get merchants_path

    expect(response.body).not_to include("page=2")
  end

  def table_rows
    Nokogiri::HTML(response.body).css("tbody tr").size
  end
end
