require "rails_helper"

RSpec.describe "Table headers", type: :request do
  let(:user) { create(:user) }

  before do
    post user_session_path, params: { user: { email: user.email, password: "password123456" } }
  end

  it "names merchant columns after what they show" do
    create(:merchant)

    get merchants_path

    expect(headers).to eq([ "Merchant", "Email address", "Live since", "Disbursement frequency", "Minimum monthly fee" ])
  end

  it "names order columns after what they show" do
    merchant = create(:merchant)
    create(:order, merchant:)

    get merchant_orders_path(merchant)

    expect(headers).to eq([ "Order", "Order date", "Order amount", "Order fee" ])
  end

  it "names disbursement columns after what they show" do
    create(:disbursement)

    get disbursements_path

    expect(headers).to eq([ "Disbursement", "Disbursement date", "Orders total", "Order fee", "Amount disbursed" ])
  end

  it "names monthly fee columns after what they show" do
    create(:monthly_fee)

    get monthly_fees_path

    expect(headers).to eq([ "Merchant", "Year", "Month", "Order fees", "Monthly fee" ])
  end

  it "names csv import columns after what they show" do
    create(:csv_import)

    get csv_imports_path

    expect(headers).to eq([ "Status", "Import type", "Rows imported", "Failed rows", "Started" ])
  end

  def headers
    Nokogiri::HTML(response.body).css("thead th").map { |header| header.text.strip }
  end
end
