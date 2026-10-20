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

  # First settlement day on or after the natural day that does not already
  # have a disbursement. Weekly steps by 7 because the natural day is already
  # the live_on weekday.
  OPEN_DUE_DAY_SQL = <<~SQL.squish
    (
      SELECT gs.day::date
      FROM generate_series(
        (#{DUE_DAY_SQL})::timestamp,
        :through::timestamp,
        CASE WHEN merchants.disbursement_frequency = 'WEEKLY' THEN interval '7 days' ELSE interval '1 day' END
      ) AS gs(day)
      WHERE NOT EXISTS (
        SELECT 1 FROM disbursements
        WHERE disbursements.merchant_id = orders.merchant_id
          AND disbursements.disbursed_on = gs.day::date
      )
      ORDER BY gs.day
      LIMIT 1
    )
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
    natural, shifted = merchants.partition { |merchant| natural_day_free?(merchant) }

    disburse_on_natural_day(natural)
    disburse_on_next_open_day(shifted)
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

  # The natural day and the first open day are the same date when every
  # existing disbursement is older than the first unpaid order. That is the
  # path that groups 1.3 million orders without probing disbursements per row.
  def natural_day_free?(merchant)
    first_due = due_orders(merchant).minimum(Arel.sql(DUE_DAY_SQL))
    return true if first_due.nil?

    newest = Disbursement.where(merchant:).maximum(:disbursed_on)
    newest.nil? || newest < first_due
  end

  def due_orders(scope)
    Order.joins(:merchant).undisbursed.where(merchant: scope).where("orders.ordered_on >= merchants.live_on")
  end

  def disburse_on_natural_day(merchants)
    return if merchants.empty?

    references = reference_by_merchant_id(merchants)

    Disbursement.transaction do
      rows = due_orders(merchants)
        .group("orders.merchant_id", Arel.sql(DUE_DAY_SQL))
        .having("#{DUE_DAY_SQL} <= ?", through)
        .pluck("orders.merchant_id", Arel.sql(DUE_DAY_SQL), Arel.sql("SUM(orders.amount_cents)"), Arel.sql("SUM(orders.commission_cents)"))
      return if rows.empty?

      insert_disbursements(rows, references)
      Order.connection.exec_update(
        Order.sanitize_sql_array([ ASSIGN_GROUPED_ORDERS_SQL, merchant_ids: references.keys, through: through, now: Time.current ])
      )
    end
  end

  # The open day is computed once, before the insert. Recomputing it afterwards
  # would skip the disbursement this statement just created.
  def disburse_on_next_open_day(merchants)
    return if merchants.empty?

    references = reference_by_merchant_id(merchants)

    Disbursement.transaction do
      snapshot_open_days(references.keys)
      rows = open_day_totals
      return if rows.empty?

      insert_disbursements(rows, references)
      assign_snapshotted_orders
    end
  end

  def reference_by_merchant_id(merchants)
    merchants.to_h { |merchant| [ merchant.id.to_s, merchant.reference ] }
  end

  def insert_disbursements(rows, references)
    Disbursement.insert_all!(rows.map { |merchant_id, disbursed_on, gross_cents, commission_cents|
      merchant_id = merchant_id.to_s
      disbursed_on = disbursed_on.to_date
      gross_cents = gross_cents.to_i
      commission_cents = commission_cents.to_i
      {
        merchant_id: merchant_id,
        disbursed_on: disbursed_on,
        reference: Disbursement.build_reference(references.fetch(merchant_id), disbursed_on),
        gross_cents: gross_cents,
        commission_cents: commission_cents,
        net_cents: gross_cents - commission_cents
      }
    })
  end

  def snapshot_open_days(merchant_ids)
    Order.connection.execute("DROP TABLE IF EXISTS backfill_due_orders")
    Order.connection.execute(Order.sanitize_sql_array([ <<~SQL.squish, { merchant_ids: merchant_ids, through: through } ]))
      CREATE TEMP TABLE backfill_due_orders AS
      SELECT order_id, merchant_id, disbursed_on, amount_cents, commission_cents
      FROM (
        SELECT orders.id AS order_id,
               orders.merchant_id,
               #{OPEN_DUE_DAY_SQL} AS disbursed_on,
               orders.amount_cents,
               orders.commission_cents
        FROM orders
        JOIN merchants ON merchants.id = orders.merchant_id
        WHERE orders.merchant_id IN (:merchant_ids)
          AND orders.disbursement_id IS NULL
          AND orders.ordered_on >= merchants.live_on
      ) due
      WHERE disbursed_on IS NOT NULL AND disbursed_on <= :through
    SQL
  end

  def open_day_totals
    Order.connection.select_rows(<<~SQL.squish)
      SELECT merchant_id, disbursed_on, SUM(amount_cents), SUM(commission_cents)
      FROM backfill_due_orders
      GROUP BY merchant_id, disbursed_on
    SQL
  end

  def assign_snapshotted_orders
    Order.connection.exec_update(
      Order.sanitize_sql_array([ <<~SQL.squish, { now: Time.current } ])
        UPDATE orders
        SET disbursement_id = disbursements.id, updated_at = :now
        FROM backfill_due_orders
        JOIN disbursements
          ON disbursements.merchant_id = backfill_due_orders.merchant_id
         AND disbursements.disbursed_on = backfill_due_orders.disbursed_on
        WHERE orders.id = backfill_due_orders.order_id
      SQL
    )
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
