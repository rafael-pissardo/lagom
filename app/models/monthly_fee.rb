class MonthlyFee < ApplicationRecord
  include RefreshesYearlyReport

  belongs_to :merchant
  has_many :adjustments, class_name: "MonthlyFeeAdjustment", dependent: :restrict_with_exception

  validates :year, presence: true
  validates :month, presence: true, inclusion: { in: 1..12 }
  validates :commissions_cents, :charged_cents,
            presence: true,
            numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validates :month, uniqueness: { scope: [ :merchant_id, :year ] }

  scope :charged, -> { where("charged_cents > 0") }
  scope :zero, -> { where(charged_cents: 0) }
  scope :in_month, ->(date) { where(year: date.year, month: date.month) }

  def known_commissions_cents
    own_adjustments.map(&:commissions_cents).max || commissions_cents
  end

  def credited_cents
    own_adjustments.sum(&:credit_cents)
  end

  def carried_credit_cents
    adjustments.select(&:carried).sum(&:credit_cents)
  end

  private

  def own_adjustments
    adjustments.reject(&:carried)
  end
end
