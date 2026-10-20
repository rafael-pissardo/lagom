class DisburseMerchantService
  class AssociationError < StandardError; end

  def self.call(merchant:, as_of:)
    new(merchant:, as_of:).call
  end

  def initialize(merchant:, as_of:)
    @merchant = merchant
    @as_of = as_of.to_date
  end

  def call
    return unless eligible_today?

    Merchant.transaction(requires_new: true) do
      merchant.lock!
      return if Disbursement.exists?(merchant: merchant, disbursed_on: as_of)

      orders = eligible_orders.reorder(:id).lock.to_a
      return if orders.empty?

      gross_cents = orders.sum(&:amount_cents)
      commission_cents = orders.sum(&:commission_cents)
      disbursement = Disbursement.create!(
        merchant: merchant,
        disbursed_on: as_of,
        reference: Disbursement.build_reference(merchant.reference, as_of),
        gross_cents: gross_cents,
        commission_cents: commission_cents,
        net_cents: gross_cents - commission_cents
      )
      associated = Order.where(id: orders.map(&:id), disbursement_id: nil).update_all(
        disbursement_id: disbursement.id,
        updated_at: Time.current
      )
      raise AssociationError, "associated #{associated} of #{orders.size} orders" unless associated == orders.size
    end
  end

  private

  attr_reader :merchant, :as_of

  def eligible_today?
    return true if merchant.daily?

    as_of.wday == merchant.live_on_weekday
  end

  def eligible_orders
    cutoff = as_of - 1.day

    merchant.orders
      .undisbursed
      .ordered_on_or_after(merchant.live_on)
      .ordered_on_or_before(cutoff)
      .order(:ordered_on, :id)
  end
end
