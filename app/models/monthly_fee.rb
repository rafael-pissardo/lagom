class MonthlyFee < ApplicationRecord
  include RefreshesYearlyReport

  belongs_to :merchant

  validates :year, presence: true
  validates :month, presence: true, inclusion: { in: 1..12 }
  validates :commissions_cents, :charged_cents,
            presence: true,
            numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validates :month, uniqueness: { scope: [ :merchant_id, :year ] }

  scope :charged, -> { where("charged_cents > 0") }
  scope :zero, -> { where(charged_cents: 0) }
  scope :in_month, ->(date) { where(year: date.year, month: date.month) }
end
