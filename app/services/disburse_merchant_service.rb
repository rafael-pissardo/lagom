class DisburseMerchantService
  class AssociationError < StandardError; end

  BATCH_DAYS = 100

  def self.call(merchant:, as_of:)
    new(merchant:, as_of:).call
  end

  def initialize(merchant:, as_of:)
    @merchant = merchant
    @as_of = as_of.to_date
  end

  def call
    loop { break if disburse_batch.zero? }
  end

  private

  attr_reader :merchant, :as_of

  def disburse_batch
    Merchant.transaction(requires_new: true) do
      merchant.lock!
      settlement_day = settlement_day_for(next_settlement_start)
      days = pending_days(settlement_day)
      next 0 if days.empty?

      Disbursement.insert_all!(disbursement_rows(days), returning: false)
      associate_orders(settlement_day, days)
      days.size
    end
  end

  def next_settlement_start
    last_disbursed_on = Disbursement.where(merchant_id: merchant.id).maximum(:disbursed_on)
    last_disbursed_on ? last_disbursed_on.next_day : merchant.live_on
  end

  # The day an order is paid: the first settlement day after ordered_on that is not
  # before start_on. Daily merchants settle every day. Weekly merchants settle on the
  # weekday of live_on.
  def settlement_day_for(start_on)
    orders = Order.arel_table
    first_day = Arel::Nodes::NamedFunction.new("GREATEST", [ cast(start_on, "date"), orders[:ordered_on] + 1 ])
    return first_day if merchant.daily?

    weekday = cast(Arel::Nodes::Extract.new(first_day, "dow"), "integer")
    days_ahead = Arel::Nodes::InfixOperation.new("%", Arel::Nodes.build_quoted(merchant.live_on_weekday) - weekday + 7, 7)
    first_day + days_ahead
  end

  def cast(value, type)
    Arel::Nodes::NamedFunction.new("CAST", [ Arel::Nodes.build_quoted(value).as(type) ])
  end

  def pending_orders
    Order.where(merchant_id: merchant.id)
      .undisbursed
      .ordered_on_or_after(merchant.live_on)
      .ordered_on_or_before(as_of - 1.day)
  end

  def pending_days(settlement_day)
    orders = Order.arel_table
    pending_orders
      .where(settlement_day.lteq(as_of))
      .group(settlement_day)
      .order(settlement_day)
      .limit(BATCH_DAYS)
      .pluck(settlement_day, Arel.star.count, orders[:amount_cents].sum, orders[:commission_cents].sum)
  end

  def disbursement_rows(days)
    days.map do |disbursed_on, _count, gross_cents, commission_cents|
      {
        merchant_id: merchant.id,
        disbursed_on: disbursed_on,
        reference: Disbursement.build_reference,
        gross_cents: gross_cents,
        commission_cents: commission_cents,
        net_cents: gross_cents - commission_cents
      }
    end
  end

  def associate_orders(settlement_day, days)
    disbursements = Disbursement.arel_table
    paid = Disbursement
      .where(merchant_id: merchant.id)
      .where(disbursements[:disbursed_on].eq(settlement_day))
      .select(:id)
      .arel
      .ast
    expected = days.sum { |_day, count, _gross, _commission| count }

    associated = pending_orders
      .where(settlement_day.lteq(days.last.first))
      .update_all(disbursement_id: Arel::Nodes::Grouping.new(paid), updated_at: Time.current)
    raise AssociationError, "associated #{associated} of #{expected} orders" unless associated == expected
  end
end
