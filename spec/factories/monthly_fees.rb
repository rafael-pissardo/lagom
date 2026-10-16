FactoryBot.define do
  factory :monthly_fee do
    merchant
    year { 2022 }
    month { 9 }
    commissions_cents { 0 }
    charged_cents { merchant.minimum_monthly_fee_cents }
  end
end
