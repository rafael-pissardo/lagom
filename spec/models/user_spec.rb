require "rails_helper"

RSpec.describe User do
  it "authenticates with email and password" do
    user = create(:user, email: "ops@lagom.test", password: "password123456")

    expect(user.valid_password?("password123456")).to be(true)
    expect(user.valid_password?("wrong")).to be(false)
    expect(User.find_for_authentication(email: "ops@lagom.test")).to eq(user)
  end

  it "uses Devise for email and password only" do
    expect(User.devise_modules).to contain_exactly(:database_authenticatable, :validatable)
  end
end
