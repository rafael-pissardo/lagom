class Merchant < ApplicationRecord
  FREQUENCIES = %w[DAILY WEEKLY].freeze

  has_many :orders, dependent: :restrict_with_exception
  has_many :disbursements, dependent: :restrict_with_exception
  has_many :monthly_fees, dependent: :restrict_with_exception

  validates :reference, presence: true, uniqueness: true
  validates :email, presence: true
  validates :live_on, presence: true
  validates :disbursement_frequency, presence: true, inclusion: { in: FREQUENCIES }
  validates :minimum_monthly_fee_cents, presence: true, numericality: { greater_than_or_equal_to: 0, only_integer: true }

  scope :daily, -> { where(disbursement_frequency: "DAILY") }
  scope :weekly, -> { where(disbursement_frequency: "WEEKLY") }

  def daily?
    disbursement_frequency == "DAILY"
  end

  def weekly?
    disbursement_frequency == "WEEKLY"
  end

  def live_on_weekday
    live_on.wday
  end
end
