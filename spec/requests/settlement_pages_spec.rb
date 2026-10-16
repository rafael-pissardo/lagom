require "rails_helper"

RSpec.describe "Settlement pages", type: :request do
  let(:user) { create(:user) }
  let(:merchant) { create(:merchant, reference: "pages_co", live_on: Date.new(2022, 9, 1)) }

  before do
    post session_path, params: { email_address: user.email_address, password: "password123456" }
  end

  it "renders disbursements index and show" do
    disbursement = create(
      :disbursement,
      merchant: merchant,
      disbursed_on: Date.new(2022, 9, 5),
      reference: "pages_co20220905"
    )
    create(:order, merchant: merchant, disbursement: disbursement, ordered_on: Date.new(2022, 9, 4))

    get disbursements_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("pages_co20220905")

    get disbursement_path(disbursement)
    expect(response).to have_http_status(:ok)
  end

  it "renders monthly fees, yearly report, orders, and csv import pages" do
    create(:monthly_fee, merchant: merchant, year: 2022, month: 9, charged_cents: 10)
    create(:order, merchant: merchant, ordered_on: Date.new(2022, 9, 4))

    get monthly_fees_path
    expect(response).to have_http_status(:ok)

    get reports_yearly_path
    expect(response).to have_http_status(:ok)

    get merchant_orders_path(merchant)
    expect(response).to have_http_status(:ok)

    get csv_imports_path
    expect(response).to have_http_status(:ok)

    get new_csv_import_path
    expect(response).to have_http_status(:ok)

    csv_import = create(:csv_import, status: "succeeded", merchants_imported_count: 1, orders_imported_count: 1)
    get csv_import_path(csv_import)
    expect(response).to have_http_status(:ok)
  end
end
