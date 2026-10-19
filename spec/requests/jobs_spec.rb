require "rails_helper"

RSpec.describe "Mission Control jobs", type: :request do
  it "redirects an anonymous operator to sign in" do
    get "/jobs"

    expect(response).to redirect_to(new_user_session_path)
  end

  it "shows the queues to a signed-in operator" do
    user = create(:user)
    post user_session_path, params: { user: { email: user.email, password: "password123456" } }

    get "/jobs"

    expect(response).to have_http_status(:ok)
  end
end
