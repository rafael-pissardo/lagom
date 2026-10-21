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
    return unless merchant.settles_on?(as_of)

    Merchant.transaction(requires_new: true) do
      merchant.lock!
      next if disbursed_today?

      count, gross_cents, commission_cents = pending_totals
      next if count.to_i.zero?

      Disbursement.insert_all!([ disbursement_row(gross_cents, commission_cents) ], returning: false)
      associate_orders(count)
    end
  end

  private

  attr_reader :merchant, :as_of

  def disbursed_today?
    Disbursement.exists?(merchant_id: merchant.id, disbursed_on: as_of)
  end

  def pending_orders
    Order.where(merchant_id: merchant.id)
      .undisbursed
      .ordered_on_or_after(merchant.live_on)
      .ordered_on_or_before(as_of - 1.day)
  end

  def pending_totals
    orders = Order.arel_table
    pending_orders.pick(Arel.star.count, orders[:amount_cents].sum, orders[:commission_cents].sum)
  end

  def disbursement_row(gross_cents, commission_cents)
    {
      merchant_id: merchant.id,
      disbursed_on: as_of,
      reference: Disbursement.build_reference,
      gross_cents: gross_cents,
      commission_cents: commission_cents,
      net_cents: gross_cents - commission_cents
    }
  end

  def associate_orders(expected)
    disbursement_id = Disbursement.where(merchant_id: merchant.id, disbursed_on: as_of).pick(:id)
    associated = pending_orders.update_all(disbursement_id:, updated_at: Time.current)
    return if associated == expected

    raise AssociationError, "associated #{associated} of #{expected} orders"
  end
end
