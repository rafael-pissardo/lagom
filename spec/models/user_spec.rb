require "rails_helper"

RSpec.describe User do
  it "authenticates with email and password" do
    user = create(:user, email_address: "ops@lagom.test", password: "password123456")

    expect(User.authenticate_by(email_address: "ops@lagom.test", password: "password123456")).to eq(user)
    expect(User.authenticate_by(email_address: "ops@lagom.test", password: "wrong")).to be_nil
  end
end
