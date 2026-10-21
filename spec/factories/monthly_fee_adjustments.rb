FactoryBot.define do
  factory :monthly_fee_adjustment do
    monthly_fee
    commissions_cents { 48 }
    credit_cents { 48 }
    carried { false }
  end
end
