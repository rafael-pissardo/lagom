class MonthlyFeeAdjustment < ApplicationRecord
  belongs_to :monthly_fee

  validates :commissions_cents, :credit_cents,
            presence: true,
            numericality: { greater_than_or_equal_to: 0, only_integer: true }
end
