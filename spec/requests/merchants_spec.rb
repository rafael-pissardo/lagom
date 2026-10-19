require "rails_helper"

RSpec.describe "Merchants", type: :request do
  it "requires authentication" do
    get merchants_path
    expect(response).to redirect_to(new_user_session_path)
  end

  it "lists merchants for a signed-in operator" do
    user = create(:user)
    merchant = create(:merchant, reference: "visible_co")
    post user_session_path, params: { user: { email: user.email, password: "password123456" } }

    get merchants_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("visible_co")
    expect(response.body).to include("DAILY")
    expect(response.body).to include("04/09/2022")
    expect(response.body).not_to include("2022-09-04")

    nav = Nokogiri::HTML(response.body).at_css("nav")
    expect(nav.css("a").map { |link| link["href"] }).not_to include("/jobs")
    expect(nav.text).not_to include("Jobs")

    get merchant_path(merchant)
    expect(response).to have_http_status(:ok)
  end
end
