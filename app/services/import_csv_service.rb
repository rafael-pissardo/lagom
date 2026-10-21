class ImportCsvService
  class RowError < StandardError
    attr_reader :line, :column

    def initialize(line, column, message)
      @line = line
      @column = column
      super(message)
    end
  end

  class Rejected < StandardError; end

  ALREADY_PROCESSED_MESSAGE = "has already been processed and cannot be imported again"

  STRATEGIES = {
    "merchants" => MerchantsService,
    "orders" => OrdersService
  }.freeze
  BOM = "\xEF\xBB\xBF".b
  ALLOWED_CHARACTERS = /\A[\nA-Za-z0-9.;@_-]*\z/

  def self.batch_size
    Integer(ENV.fetch("CSV_IMPORT_BATCH_SIZE", 500))
  end

  def self.call(csv_import:)
    new(csv_import:).call
  end

  def initialize(csv_import:)
    @csv_import = csv_import
    @errors = []
    @imported_count = 0
    @constraint_error = nil
    @file_error = nil
  end

  def call
    mark_processing
    return finish_failure(file_error) unless import_file

    finish_success
  rescue Rejected
    finish_failure(@constraint_error)
  rescue StandardError => error
    finish_failure(error.message)
    raise
  end

  private

  attr_reader :csv_import, :errors, :imported_count, :file_error

  def mark_processing
    csv_import.update!(
      status: "processing",
      started_at: Time.current,
      error_message: nil,
      error_rows: [],
      imported_count: 0,
      failed_count: 0
    )
  end

  def import_file
    BucketService.open(csv_import.object_key) do |io|
      raw = io.read
      io.rewind
      return false unless acceptable_file?(raw)

      read_rows(io)
      return false if errors.any?

      io.rewind
      strategy.guard_concurrent_changes!
      ActiveRecord::Base.transaction(requires_new: true) do
        write_rows(io)
      end
      true
    end
  rescue ActiveRecord::RecordNotUnique => error
    @constraint_error = error.message
    raise Rejected
  end

  def acceptable_file?(raw)
    if raw.b.start_with?(BOM)
      reject_file("CSV contains characters outside the SeQura files")
      return false
    end

    text = raw.dup.force_encoding(Encoding::UTF_8)
    unless text.valid_encoding?
      reject_file("CSV is not valid UTF-8")
      return false
    end

    unless text.match?(ALLOWED_CHARACTERS)
      reject_file("CSV contains characters outside the SeQura files")
      return false
    end

    lines = text.lines
    header = lines.first&.chomp
    if header.blank?
      reject_file("CSV has no rows")
      return false
    end

    extra = header.split(";", -1) - strategy.class.csv_headers
    if extra.any?
      reject_file("CSV is not the model used by SeQura", column: extra.first)
      return false
    end

    if lines.drop(1).none? { |line| line.strip.present? }
      reject_file("CSV has no rows")
      return false
    end

    true
  end

  def reject_file(message, column: nil)
    @file_error = message
    return if column.nil?

    errors << { "line" => 1, "column" => column, "message" => message }
  end

  def read_rows(io)
    each_batch(io) { |batch| errors.concat(strategy.prepare_batch(batch).last) }
  end

  def write_rows(io)
    each_batch(io) do |batch|
      rows, batch_errors = strategy.prepare_batch(batch, lock: true)
      errors.concat(batch_errors)
      next if errors.any?

      strategy.upsert(rows)
      @imported_count += rows.size
    end
    raise Rejected if errors.any?
  end

  def each_batch(io)
    CsvBatchReaderService.each(io:, batch_size: self.class.batch_size) { |batch| yield batch }
  end

  def strategy
    @strategy ||= STRATEGIES.fetch(csv_import.kind) { raise ArgumentError, "unknown import kind" }.new(merchant_cache:)
  end

  def merchant_cache
    @merchant_cache ||= MerchantCacheService.new(batch_size: self.class.batch_size)
  end

  def finish_success
    csv_import.update!(
      status: "succeeded",
      finished_at: Time.current,
      error_rows: [],
      imported_count: imported_count,
      failed_count: 0
    )
  end

  def finish_failure(message = nil)
    csv_import.update!(
      status: "failed",
      finished_at: Time.current,
      error_message: message,
      error_rows: errors,
      imported_count: 0,
      failed_count: errors.size
    )
  end
end
