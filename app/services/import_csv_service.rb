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

  class InvalidFile < StandardError; end

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
      stream = Stream.new(io)
      return false unless acceptable_stream?(stream)

      stream.rewind
      read_rows(stream)
      return false if errors.any?

      stream.rewind
      strategy.guard_concurrent_changes!
      ActiveRecord::Base.transaction(requires_new: true) do
        ActiveRecord::Base.with_advisory_lock!("csv_import:#{csv_import.kind}", transaction: true, blocking: true) do
          write_rows(stream)
        end
      end
      true
    end
  rescue InvalidFile => error
    errors.clear
    reject_file(error.message)
    false
  rescue ActiveRecord::RecordNotUnique => error
    @constraint_error = error.message
    raise Rejected
  end

  def acceptable_stream?(stream)
    header_line = stream.gets
    if header_line.nil? || header_line.strip.empty?
      reject_file("CSV has no rows")
      return false
    end

    extra = header_line.chomp.split(";", -1) - strategy.class.csv_headers
    if extra.any?
      reject_file("CSV is not the model used by SeQura", column: extra.first)
      return false
    end

    content = false
    while (line = stream.gets)
      content = true if line.strip.present?
    end
    return true if content

    reject_file("CSV has no rows")
    false
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

      strategy.write(rows)
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
