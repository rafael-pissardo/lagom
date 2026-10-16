require "rails_helper"

RSpec.describe "Sessions", type: :request do
  it "signs the operator in and out" do
    create(:user, email: "ops@lagom.test", password: "password123456")

    post user_session_path, params: { user: { email: "ops@lagom.test", password: "password123456" } }
    expect(response).to redirect_to(root_url)
    follow_redirect!
    expect(response.body).to include("Merchants")

    delete destroy_user_session_path
    expect(response).to redirect_to(new_user_session_path)
  end
end
