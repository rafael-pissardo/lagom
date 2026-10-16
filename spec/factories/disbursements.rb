FactoryBot.define do
  factory :disbursement do
    merchant
    disbursed_on { Date.new(2022, 9, 5) }
    reference { Disbursement.build_reference(merchant.reference, disbursed_on) }
    gross_cents { 6_174 }
    commission_cents { 59 }
    net_cents { gross_cents - commission_cents }
  end
end
