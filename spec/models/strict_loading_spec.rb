require "rails_helper"

RSpec.describe "strict loading" do
  it "raises when a collection lazy-loads a belongs_to" do
    create(:monthly_fee)
    fees = MonthlyFee.order(:id).to_a

    expect { fees.each { |fee| fee.merchant.reference } }
      .to raise_error(ActiveRecord::StrictLoadingViolationError)
  end

  it "raises when a collection lazy-loads a has_many" do
    create(:order)
    merchants = Merchant.order(:id).to_a

    expect { merchants.each { |merchant| merchant.orders.to_a } }
      .to raise_error(ActiveRecord::StrictLoadingViolationError)
  end

  it "allows a preloaded belongs_to" do
    create(:monthly_fee)
    fees = MonthlyFee.includes(:merchant).order(:id).to_a

    expect { fees.each { |fee| fee.merchant.reference } }.not_to raise_error
  end
end
