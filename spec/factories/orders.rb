FactoryBot.define do
  factory :order do
    merchant
    sequence(:external_id) { |n| format("%012x", n) }
    ordered_on { merchant.live_on }
    amount_cents { 6_174 }
    commission_cents { Commission.cents_for(amount_cents) }
  end
end
