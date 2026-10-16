require "rails_helper"

RSpec.describe "Merchants", type: :request do
  it "requires authentication" do
    get merchants_path
    expect(response).to redirect_to(new_session_path)
  end

  it "lists merchants for a signed-in operator" do
    user = create(:user)
    merchant = create(:merchant, reference: "visible_co")
    post session_path, params: { email_address: user.email_address, password: "password123456" }

    get merchants_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("visible_co")

    get merchant_path(merchant)
    expect(response).to have_http_status(:ok)
  end
end
