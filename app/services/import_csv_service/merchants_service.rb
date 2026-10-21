class ImportCsvService::MerchantsService
  include ImportCsvService::CsvRow
  include UuidHelper

  def self.csv_headers
    COLUMNS.values.uniq
  end

  COLUMNS = {
    id: "id",
    reference: "reference",
    email: "email",
    live_on: "live_on",
    disbursement_frequency: "disbursement_frequency",
    minimum_monthly_fee_cents: "minimum_monthly_fee"
  }.freeze

  UPDATE_COLUMNS = %i[reference email live_on disbursement_frequency minimum_monthly_fee_cents].freeze

  def initialize(merchant_cache:)
    @merchant_cache = merchant_cache
    @accepted_ids = Set.new
    reset_claims!
  end

  def guard_concurrent_changes!
    reset_claims!
    merchant_cache.reset!
  end

  def prepare_batch(batch, **)
    parsed, errors = parse_batch(batch)
    remember(parsed)
    errors.concat(already_processed_errors(parsed))
    fresh = parsed.reject { |_line, attrs| processed_id?(attrs.fetch(:id)) }
    kept = last_entries(fresh, :id)
    errors.concat(claim_entries(kept))
    [ kept.map(&:last), errors ]
  end

  def attributes(row, line_number)
    id = value(row, "id", line_number)
    reference = value(row, "reference", line_number)
    email = value(row, "email", line_number)
    live_on = date_value(row, "live_on", line_number)
    frequency = value(row, "disbursement_frequency", line_number)
    minimum_monthly_fee_cents = money_value(row, "minimum_monthly_fee", line_number)
    ensure_frequency!(frequency, line_number)
    raise ImportCsvService::RowError.new(line_number, "id", "is invalid") unless uuid?(id)

    {
      id: id,
      reference: reference,
      email: email,
      live_on: live_on,
      disbursement_frequency: frequency,
      minimum_monthly_fee_cents: minimum_monthly_fee_cents
    }
  end

  def write(rows)
    return if rows.empty?

    fresh, own = rows.partition { |row| !accepted_ids.include?(row.fetch(:id)) }
    Merchant.insert_all!(fresh, returning: false) if fresh.any?
    Merchant.upsert_all(own, unique_by: :id, update_only: UPDATE_COLUMNS, returning: false) if own.any?
    @accepted_ids.merge(rows.map { |row| row.fetch(:id) })
  end

  private

  attr_reader :merchant_cache, :accepted_ids

  def reset_claims!
    @owner_by_reference = {}
    @reference_by_id = {}
    @claimed_ids = Set.new
    @released = Set.new
  end

  def parse_batch(batch)
    parsed = []
    errors = batch.each_with_object([]) do |(row, line_number), found|
      parsed << [ line_number, attributes(row, line_number) ]
    rescue ImportCsvService::RowError => error
      found << row_error(error)
    end
    [ parsed, errors ]
  end

  def remember(entries)
    return if entries.empty?

    ids = entries.map { |_line, attrs| attrs.fetch(:id) }
    references = entries.map { |_line, attrs| attrs.fetch(:reference) }
    merchant_cache.load_ids(ids)
    merchant_cache.load_references(references)
    ids.each { |id| remember_id(id) }
    references.each { |reference| remember_reference(reference) }
  end

  def remember_id(id)
    return if @claimed_ids.include?(id) || @reference_by_id.key?(id)

    merchant = merchant_cache.by_id(id)
    return if merchant.nil?

    @reference_by_id[id] = merchant.reference
    @owner_by_reference[merchant.reference] = id unless @released.include?(merchant.reference)
  end

  def remember_reference(reference)
    return if @owner_by_reference.key?(reference) || @released.include?(reference)

    merchant = merchant_cache.fetch(reference)
    return if merchant.nil? || @claimed_ids.include?(merchant.id)

    @owner_by_reference[reference] = merchant.id
    @reference_by_id[merchant.id] ||= merchant.reference
  end

  def already_processed_errors(entries)
    entries.filter_map do |line_number, attrs|
      next unless processed_id?(attrs.fetch(:id))

      { "line" => line_number, "column" => "id", "message" => ImportCsvService::ALREADY_PROCESSED_MESSAGE }
    end
  end

  def processed_id?(id)
    return false if accepted_ids.include?(id)

    !merchant_cache.by_id(id).nil?
  end

  def claim_entries(entries)
    entries.each_with_object([]) do |(line_number, attrs), found|
      claim_reference!(attrs.fetch(:id), attrs.fetch(:reference), line_number)
    rescue ImportCsvService::RowError => error
      found << row_error(error)
    end
  end

  def claim_reference!(id, reference, line_number)
    release_previous_reference(id, reference)
    owner = @owner_by_reference[reference]
    if owner && owner != id
      record = Merchant.new
      record.errors.add(:reference, :taken)
      raise_row_error!(record, line_number, COLUMNS)
    end

    @owner_by_reference[reference] = id
    @reference_by_id[id] = reference
    @claimed_ids << id
  end

  def release_previous_reference(id, reference)
    previous = @reference_by_id[id]
    return if previous.nil? || previous == reference

    @owner_by_reference.delete(previous)
    @released << previous
  end

  def ensure_frequency!(frequency, line_number)
    return if Merchant.disbursement_frequencies.value?(frequency)

    record = Merchant.new
    record.errors.add(:disbursement_frequency, :inclusion)
    raise_row_error!(record, line_number, COLUMNS)
  end
end
