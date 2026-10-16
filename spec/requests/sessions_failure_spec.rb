require "rails_helper"

RSpec.describe "Sessions failures", type: :request do
  it "rejects invalid credentials" do
    create(:user, email_address: "ops@lagom.test", password: "password123456")

    post session_path, params: { email_address: "ops@lagom.test", password: "nope" }

    expect(response).to redirect_to(new_session_path)
    follow_redirect!
    expect(response.body).to include("Invalid email or password")
  end
end
