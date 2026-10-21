class ImportCsvService::OrdersService
  include ImportCsvService::CsvRow

  def self.csv_headers
    COLUMNS.values.uniq
  end

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
    @accepted_ids = Set.new
    @found_external_ids = Set.new
  end

  def guard_concurrent_changes!
    merchant_cache.reset!
  end

  def prepare_batch(batch, lock: false)
    merchant_cache.load_references(batch.filter_map { |row, _line| row["merchant_reference"]&.strip })
    parsed, errors = parse_batch(batch)
    errors.concat(already_processed_errors(parsed, lock:))
    fresh = parsed.reject { |_line, attrs| processed_external_id?(attrs.fetch(:external_id)) }
    kept = last_entries(fresh, :external_id)
    [ kept.map(&:last), errors ]
  end

  def attributes(row, line_number)
    reference = value(row, "merchant_reference", line_number)
    merchant = merchant_cache.fetch(reference)
    raise ImportCsvService::RowError.new(line_number, "merchant_reference", "is unknown") if merchant.nil?

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

  def write(rows)
    return if rows.empty?

    fresh, own = rows.partition { |row| !@accepted_ids.include?(row.fetch(:external_id)) }
    Order.insert_all!(fresh, returning: false) if fresh.any?
    Order.upsert_all(own, unique_by: :external_id, update_only: UPDATE_COLUMNS, returning: false) if own.any?
    @accepted_ids.merge(rows.map { |row| row.fetch(:external_id) })
  end

  private

  attr_reader :merchant_cache

  def parse_batch(batch)
    parsed = []
    errors = batch.each_with_object([]) do |(row, line_number), found|
      parsed << [ line_number, attributes(row, line_number) ]
    rescue ImportCsvService::RowError => error
      found << row_error(error)
    end
    [ parsed, errors ]
  end

  def already_processed_errors(entries, lock:)
    @found_external_ids = existing_external_ids(entries, lock:)
    entries.filter_map do |line_number, attrs|
      external_id = attrs.fetch(:external_id)
      next unless processed_external_id?(external_id)

      { "line" => line_number, "column" => "id", "message" => ImportCsvService::ALREADY_PROCESSED_MESSAGE }
    end
  end

  def existing_external_ids(entries, lock:)
    return Set.new if entries.empty?

    existing_orders(entries.map { |_line, attrs| attrs.fetch(:external_id) }, lock:).keys.to_set
  end

  def processed_external_id?(external_id)
    return false if @accepted_ids.include?(external_id)

    @found_external_ids.include?(external_id)
  end

  def existing_orders(external_ids, lock:)
    scope = Order.where(external_id: external_ids.uniq)
    scope = scope.order(:id).lock if lock
    scope.index_by(&:external_id)
  end

  def ensure_live_on!(merchant, ordered_on, line_number)
    return if ordered_on >= merchant.live_on

    record = Order.new
    record.errors.add(:ordered_on, :before_live_on)
    raise_row_error!(record, line_number, COLUMNS)
  end
end
