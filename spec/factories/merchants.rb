FactoryBot.define do
  factory :merchant do
    id { SecureRandom.uuid }
    sequence(:reference) { |n| "merchant_#{n}" }
    sequence(:email) { |n| "merchant#{n}@example.com" }
    live_on { Date.new(2022, 9, 4) }
    disbursement_frequency { "DAILY" }
    minimum_monthly_fee_cents { 2_900 }

    trait :weekly do
      disbursement_frequency { "WEEKLY" }
    end
  end
end
