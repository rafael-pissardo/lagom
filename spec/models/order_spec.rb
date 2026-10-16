require "rails_helper"

RSpec.describe Order do
  it "rejects orders before the merchant live_on date" do
    merchant = create(:merchant, live_on: Date.new(2022, 9, 4))
    order = build(:order, merchant: merchant, ordered_on: Date.new(2022, 9, 3))

    expect(order).not_to be_valid
    expect(order.errors[:ordered_on]).to be_present
  end
end
