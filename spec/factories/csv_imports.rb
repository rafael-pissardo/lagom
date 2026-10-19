FactoryBot.define do
  factory :csv_import do
    status { "pending" }
    kind { "merchants" }
    sequence(:object_key) { |n| "merchants-20261019120000000-#{n}.csv" }
  end
end
