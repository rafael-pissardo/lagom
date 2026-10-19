class ImportCsv::Merchants
  include ImportCsv::CsvRow
  include UuidHelper

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
    @reference_owner = {}
    @reference_for_id = {}
    @ids = Set.new
    @references = Set.new
  end

  def prepare(row, line_number)
    attrs = attributes(row, line_number)
    @ids << attrs[:id]
    @references << attrs[:reference]
    attrs
  end

  def guard_concurrent_changes!
    return [] if @ids.empty?

    merchant_cache.lock_existing(ids: @ids.to_a, references: @references.to_a)
    @reference_owner = {}
    @reference_for_id = {}
    []
  end

  def review_batch(entries, **)
    return [] if entries.empty?

    ids = entries.map { |_line, attrs| attrs.fetch(:id) }
    references = entries.map { |_line, attrs| attrs.fetch(:reference) }
    merchant_cache.load_ids(ids)
    merchant_cache.load_references(references)
    merchant_cache.load_references(ids.filter_map { |id| merchant_cache.reference_for_id(id) })
    entries.each_with_object([]) do |(line_number, attrs), found|
      claim_reference!(attrs.fetch(:id), attrs.fetch(:reference), line_number)
    rescue ImportCsv::RowError => error
      found << { "line" => error.line, "column" => error.column, "message" => error.message }
    end
  end

  def attributes(row, line_number)
    id = value(row, "id", line_number)
    reference = value(row, "reference", line_number)
    email = value(row, "email", line_number)
    live_on = date_value(row, "live_on", line_number)
    frequency = value(row, "disbursement_frequency", line_number)
    minimum_monthly_fee_cents = money_value(row, "minimum_monthly_fee", line_number)
    ensure_frequency!(frequency, line_number)
    raise ImportCsv::RowError.new(line_number, "id", "is invalid") unless uuid?(id)

    {
      id: id,
      reference: reference,
      email: email,
      live_on: live_on,
      disbursement_frequency: frequency,
      minimum_monthly_fee_cents: minimum_monthly_fee_cents
    }
  end

  def upsert(rows)
    return if rows.empty?

    Merchant.upsert_all(
      last_row_per(rows, :id),
      unique_by: :id,
      update_only: UPDATE_COLUMNS,
      returning: false
    )
  end

  private

  attr_reader :merchant_cache

  def ensure_frequency!(frequency, line_number)
    return if Merchant::FREQUENCIES.include?(frequency)

    record = Merchant.new
    record.errors.add(:disbursement_frequency, :inclusion)
    raise_row_error!(record, line_number, COLUMNS)
  end

  def claim_reference!(id, reference, line_number)
    release_previous_reference(id, reference)

    owner = reference_owner(reference)
    if owner && owner != id
      record = Merchant.new
      record.errors.add(:reference, :taken)
      raise_row_error!(record, line_number, COLUMNS)
    end

    @reference_owner[reference] = id
    @reference_for_id[id] = reference
  end

  def release_previous_reference(id, reference)
    previous = @reference_for_id[id] || merchant_cache.reference_for_id(id)
    return if previous.nil? || previous == reference
    return unless reference_owner(previous) == id

    @reference_owner[previous] = nil
  end

  def reference_owner(reference)
    return @reference_owner[reference] if @reference_owner.key?(reference)

    merchant_cache.reference_id(reference)
  end
end
