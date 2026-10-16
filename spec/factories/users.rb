FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "operator#{n}@lagom.test" }
    password { "password123456" }
  end
end
