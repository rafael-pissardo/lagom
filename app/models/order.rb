class Order < ApplicationRecord
  belongs_to :merchant
  belongs_to :disbursement, optional: true

  validates :external_id, presence: true, uniqueness: true
  validates :ordered_on, presence: true
  validates :amount_cents, presence: true, numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validates :commission_cents, presence: true, numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validate :ordered_on_not_before_live_on

  scope :undisbursed, -> { where(disbursement_id: nil) }
  scope :ordered_on_or_before, ->(date) { where(ordered_on: ..date) }
  scope :ordered_on_or_after, ->(date) { where(ordered_on: date..) }

  private

  def ordered_on_not_before_live_on
    return if merchant.blank? || ordered_on.blank?
    return if ordered_on >= merchant.live_on

    errors.add(:ordered_on, :before_live_on)
  end
end
