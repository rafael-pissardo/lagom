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

  def initialize(merchant_cache:)
    @merchant_cache = merchant_cache
    @checked_orders = []
  end

  def prepare(row, line_number)
    attrs = attributes(row, line_number)
    @checked_orders << [ line_number, row.fetch("merchant_reference").strip, attrs.fetch(:ordered_on) ]
    attrs
  end

  def finish_references
    []
  end

  def guard_concurrent_changes!
    return [] if @checked_orders.empty?

    merchant_cache.lock_existing(
      ids: [],
      references: @checked_orders.map { |_line, reference, _ordered_on| reference }
    )
    @checked_orders.each_with_object([]) do |(line_number, reference, ordered_on), found|
      merchant = merchant_cache.fetch(reference)
      raise ImportCsv::RowError.new(line_number, "merchant_reference", "is unknown") if merchant.nil?

      ensure_live_on!(merchant, ordered_on, line_number)
    rescue ImportCsv::RowError => error
      found << { "line" => error.line, "column" => error.column, "message" => error.message }
    end
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

  def ensure_live_on!(merchant, ordered_on, line_number)
    return if ordered_on >= merchant.live_on

    record = Order.new
    record.errors.add(:ordered_on, :before_live_on)
    raise_row_error!(record, line_number, COLUMNS)
  end
end
