class Disbursement < ApplicationRecord
  include RefreshesYearlyReport

  belongs_to :merchant
  has_many :orders, dependent: :restrict_with_exception

  validates :disbursed_on, presence: true
  validates :reference, presence: true, uniqueness: true
  validates :gross_cents, :commission_cents, :net_cents,
            presence: true,
            numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validates :disbursed_on, uniqueness: { scope: :merchant_id }

  def self.build_reference(merchant_reference, disbursed_on)
    "#{merchant_reference}#{disbursed_on.strftime('%Y%m%d')}"
  end
end
