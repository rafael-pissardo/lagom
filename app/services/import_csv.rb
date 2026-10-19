class ImportCsv
  class RowError < StandardError
    attr_reader :line, :column

    def initialize(line, column, message)
      @line = line
      @column = column
      super(message)
    end
  end

  class Rejected < StandardError; end

  STRATEGIES = {
    "merchants" => Merchants,
    "orders" => Orders
  }.freeze

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
  end

  def call
    mark_processing

    ActiveRecord::Base.transaction(requires_new: true) do
      import_file
      raise Rejected if errors.any?
    end

    finish_success
  rescue Rejected
    finish_failure
  rescue StandardError => error
    finish_failure(error.message)
    raise
  end

  private

  attr_reader :csv_import, :errors, :imported_count

  def mark_processing
    csv_import.update!(
      status: "processing",
      started_at: Time.current,
      error_message: nil,
      error_rows: [],
      merchants_imported_count: 0,
      orders_imported_count: 0,
      merchants_failed_count: 0,
      orders_failed_count: 0
    )
  end

  def import_file
    Bucket.open(csv_import.object_key) do |io|
      read_rows(io)
      raise Rejected if errors.any?

      io.rewind
      write_rows(io)
    end
  end

  def read_rows(io)
    each_batch(io) do |batch|
      batch.each { |row, line_number| prepare_row(row, line_number) }
    end
  end

  def write_rows(io)
    each_batch(io) do |batch|
      rows = batch.map { |row, line_number| strategy.attributes(row, line_number) }
      strategy.upsert(rows)
      @imported_count += batch.size
    end
  end

  def each_batch(io)
    CsvBatchReader.each(io:, batch_size: self.class.batch_size) { |batch| yield batch }
  end

  def prepare_row(row, line_number)
    strategy.prepare(row, line_number)
  rescue RowError => error
    errors << { "line" => error.line, "column" => error.column, "message" => error.message }
  end

  def strategy
    @strategy ||= STRATEGIES.fetch(csv_import.kind) { raise ArgumentError, "unknown import kind" }.new(merchant_cache:)
  end

  def merchant_cache
    @merchant_cache ||= MerchantCache.new
  end

  def finish_success
    csv_import.update!(
      status: "succeeded",
      finished_at: Time.current,
      error_rows: [],
      merchants_imported_count: csv_import.merchants? ? imported_count : 0,
      orders_imported_count: csv_import.orders? ? imported_count : 0,
      merchants_failed_count: 0,
      orders_failed_count: 0
    )
    BackfillSettlementsJob.perform_later
  end

  def finish_failure(message = nil)
    failed_count = errors.size
    csv_import.update!(
      status: "failed",
      finished_at: Time.current,
      error_message: message,
      error_rows: errors,
      merchants_imported_count: 0,
      orders_imported_count: 0,
      merchants_failed_count: csv_import.merchants? ? failed_count : 0,
      orders_failed_count: csv_import.orders? ? failed_count : 0
    )
  end
end
