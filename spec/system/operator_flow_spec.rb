require "rails_helper"

RSpec.describe "Operator flow", type: :system do
  it "signs in and opens the yearly report" do
    create(:user, email_address: "ops@lagom.test", password: "password123456")
    merchant = create(:merchant, reference: "ui_co", live_on: Date.new(2022, 9, 1))
    create(
      :disbursement,
      merchant: merchant,
      disbursed_on: Date.new(2022, 9, 5),
      reference: "ui_co20220905",
      gross_cents: 10_000,
      commission_cents: 95,
      net_cents: 9_905
    )

    visit new_session_path
    fill_in "Email address", with: "ops@lagom.test"
    fill_in "Password", with: "password123456"
    click_button "Sign in"

    expect(page).to have_content("Merchants")
    visit reports_yearly_path
    expect(page).to have_content("Yearly report")
    expect(page).to have_content("2022")
  end
end
