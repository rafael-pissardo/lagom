class BackfillSettlementsService
  # The day an undisbursed order is paid when nothing is in the way:
  # daily merchants the next day, weekly merchants the next live_on weekday.
  # EXTRACT(DOW) and Date#wday both count Sunday as 0.
  DUE_DAY_SQL = <<~SQL.squish
    CASE WHEN merchants.disbursement_frequency = 'WEEKLY'
      THEN (orders.ordered_on + 1) + ((EXTRACT(DOW FROM merchants.live_on)::integer - EXTRACT(DOW FROM orders.ordered_on + 1)::integer + 7) % 7)
      ELSE orders.ordered_on + 1
    END
  SQL

  ASSIGN_GROUPED_ORDERS_SQL = <<~SQL.squish
    UPDATE orders
    SET disbursement_id = due.disbursement_id, updated_at = :now
    FROM (
      SELECT orders.id AS order_id, disbursements.id AS disbursement_id
      FROM orders
      JOIN merchants ON merchants.id = orders.merchant_id
      JOIN disbursements
        ON disbursements.merchant_id = orders.merchant_id
       AND disbursements.disbursed_on = #{DUE_DAY_SQL}
      WHERE orders.merchant_id IN (:merchant_ids)
        AND orders.disbursement_id IS NULL
        AND orders.ordered_on >= merchants.live_on
        AND disbursements.disbursed_on <= :through
    ) due
    WHERE orders.id = due.order_id
  SQL

  def self.call(as_of: nil)
    new(as_of).call
  end

  def initialize(as_of = nil)
    @as_of = as_of&.to_date || default_as_of
  end

  def call
    return if as_of.blank?

    merchants = Merchant.all.to_a
    grouped, one_by_one = merchants.partition { |merchant| groupable?(merchant) }

    disburse_grouped(grouped)
    one_by_one.each { |merchant| disburse_day_by_day(merchant) }
    merchants.each { |merchant| charge_closed_months(merchant) }
  end

  private

  attr_reader :as_of

  def default_as_of
    Order.maximum(:ordered_on)
  end

  def through
    @through ||= as_of + 7.days
  end

  # Grouping in SQL gives the same result as the day-by-day loop only when every
  # existing disbursement is older than the first day an unpaid order is due.
  def groupable?(merchant)
    first_due = due_orders(merchant).minimum(Arel.sql(DUE_DAY_SQL))
    return true if first_due.nil?

    newest = Disbursement.where(merchant:).maximum(:disbursed_on)
    newest.nil? || newest < first_due
  end

  def due_orders(scope)
    Order.joins(:merchant).undisbursed.where(merchant: scope).where("orders.ordered_on >= merchants.live_on")
  end

  def disburse_grouped(merchants)
    return if merchants.empty?

    references = merchants.to_h { |merchant| [ merchant.id, merchant.reference ] }

    Disbursement.transaction do
      rows = due_orders(merchants)
        .group("orders.merchant_id", Arel.sql(DUE_DAY_SQL))
        .having("#{DUE_DAY_SQL} <= ?", through)
        .pluck("orders.merchant_id", Arel.sql(DUE_DAY_SQL), Arel.sql("SUM(orders.amount_cents)"), Arel.sql("SUM(orders.commission_cents)"))
      return if rows.empty?

      Disbursement.insert_all!(rows.map { |merchant_id, disbursed_on, gross_cents, commission_cents|
        {
          merchant_id: merchant_id,
          disbursed_on: disbursed_on,
          reference: Disbursement.build_reference(references.fetch(merchant_id), disbursed_on),
          gross_cents: gross_cents,
          commission_cents: commission_cents,
          net_cents: gross_cents - commission_cents
        }
      })

      Order.connection.exec_update(
        Order.sanitize_sql_array([ ASSIGN_GROUPED_ORDERS_SQL, merchant_ids: references.keys, through: through, now: Time.current ])
      )
    end
  end

  # When a disbursement already sits on an order's due day, the order has to go
  # to the next open eligible day, which may be before the merchant's newest
  # disbursement. DisburseMerchantService keeps that rule, so walk the days with it and
  # only skip days where nothing is waiting.
  def disburse_day_by_day(merchant)
    due_days = due_orders(merchant).where("#{DUE_DAY_SQL} <= ?", through).distinct.pluck(Arel.sql(DUE_DAY_SQL)).to_set
    return if due_days.empty?

    taken_days = Disbursement.where(merchant:, disbursed_on: due_days.min..through).pluck(:disbursed_on).to_set
    waiting = false

    due_days.min.upto(through) do |day|
      waiting ||= due_days.include?(day)
      next unless waiting && merchant.settles_on?(day) && taken_days.exclude?(day)

      DisburseMerchantService.call(merchant: merchant, as_of: day)
      waiting = false
    end
  end

  def charge_closed_months(merchant)
    month_cursor = merchant.live_on.beginning_of_month
    last_closed_month = as_of.beginning_of_month.prev_month

    while month_cursor <= last_closed_month
      ChargeMonthlyFeeService.call(merchant: merchant, year: month_cursor.year, month: month_cursor.month)
      month_cursor = month_cursor.next_month
    end
  end
end
