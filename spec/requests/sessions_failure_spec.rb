require "rails_helper"

RSpec.describe "Sessions failures", type: :request do
  it "rejects invalid credentials" do
    create(:user, email: "ops@lagom.test", password: "password123456")

    post user_session_path, params: { user: { email: "ops@lagom.test", password: "nope" } }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Invalid email or password")
  end
end
