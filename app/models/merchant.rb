class Merchant < ApplicationRecord
  has_many :orders, dependent: :restrict_with_exception
  has_many :disbursements, dependent: :restrict_with_exception
  has_many :monthly_fees, dependent: :restrict_with_exception

  enum :disbursement_frequency, { daily: "DAILY", weekly: "WEEKLY" }, validate: true

  validates :reference, presence: true, uniqueness: true
  validates :email, presence: true
  validates :live_on, presence: true
  validates :minimum_monthly_fee_cents, presence: true, numericality: { greater_than_or_equal_to: 0, only_integer: true }

  scope :search, ->(term) {
    where("merchants.reference ILIKE :term OR merchants.email ILIKE :term", term: "%#{sanitize_sql_like(term)}%")
  }

  def live_on_weekday
    live_on.wday
  end
end
