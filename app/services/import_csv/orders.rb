class ImportCsv::Orders
  include ImportCsv::CsvRow

  COLUMNS = {
    external_id: "id",
    merchant: "merchant_reference",
    ordered_on: "created_at",
    amount_cents: "amount",
    commission_cents: "amount"
  }.freeze

  UPDATE_COLUMNS = %i[merchant_id ordered_on amount_cents commission_cents].freeze
  DISBURSED_MESSAGE = "cannot be changed after the order was disbursed"
  FINANCIAL_COLUMNS = [
    [ :merchant_id, "merchant_reference" ],
    [ :ordered_on, "created_at" ],
    [ :amount_cents, "amount" ],
    [ :commission_cents, "amount" ]
  ].freeze

  def initialize(merchant_cache:)
    @merchant_cache = merchant_cache
    @references = Set.new
  end

  def prepare(row, line_number)
    attrs = attributes(row, line_number)
    @references << row.fetch("merchant_reference").strip
    attrs
  end

  def guard_concurrent_changes!
    return [] if @references.empty?

    merchant_cache.lock_existing(ids: [], references: @references.to_a)
    []
  end

  def review_batch(entries, lock: false)
    return [] if entries.empty?

    existing = existing_orders(entries.map { |_line, attrs| attrs.fetch(:external_id) }, lock:)
    persisted_entries(entries).filter_map { |line_number, attrs| disbursed_change(line_number, existing[attrs.fetch(:external_id)], attrs) }
  end

  def attributes(row, line_number)
    reference = value(row, "merchant_reference", line_number)
    merchant = merchant_cache.fetch(reference)
    raise ImportCsv::RowError.new(line_number, "merchant_reference", "is unknown") if merchant.nil?

    amount_cents = money_value(row, "amount", line_number)
    external_id = value(row, "id", line_number)
    ordered_on = date_value(row, "created_at", line_number)
    ensure_live_on!(merchant, ordered_on, line_number)
    {
      external_id: external_id,
      merchant_id: merchant.id,
      ordered_on: ordered_on,
      amount_cents: amount_cents,
      commission_cents: Commission.cents_for(amount_cents)
    }
  end

  def upsert(rows)
    return if rows.empty?

    Order.upsert_all(
      last_row_per(rows, :external_id),
      unique_by: :external_id,
      update_only: UPDATE_COLUMNS,
      returning: false
    )
  end

  private

  attr_reader :merchant_cache

  def existing_orders(external_ids, lock:)
    scope = Order.where(external_id: external_ids.uniq)
    scope = scope.order(:id).lock if lock
    scope.index_by(&:external_id)
  end

  def persisted_entries(entries)
    entries.reverse.uniq { |_line, attrs| attrs.fetch(:external_id) }.reverse
  end

  def disbursed_change(line_number, order, attrs)
    return if order.nil? || order.disbursement_id.nil?

    _key, column = FINANCIAL_COLUMNS.find { |key, _column| order.public_send(key) != attrs.fetch(key) }
    return if column.nil?

    { "line" => line_number, "column" => column, "message" => DISBURSED_MESSAGE }
  end

  def ensure_live_on!(merchant, ordered_on, line_number)
    return if ordered_on >= merchant.live_on

    record = Order.new
    record.errors.add(:ordered_on, :before_live_on)
    raise_row_error!(record, line_number, COLUMNS)
  end
end
