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
    @constraint_error = nil
  end

  def call
    mark_processing
    return finish_failure unless import_file

    finish_success
  rescue Rejected
    finish_failure(@constraint_error)
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
      imported_count: 0,
      failed_count: 0
    )
  end

  def import_file
    Bucket.open(csv_import.object_key) do |io|
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
    CsvBatchReader.each(io:, batch_size: self.class.batch_size) { |batch| yield batch }
  end

  def strategy
    @strategy ||= STRATEGIES.fetch(csv_import.kind) { raise ArgumentError, "unknown import kind" }.new(merchant_cache:)
  end

  def merchant_cache
    @merchant_cache ||= MerchantCache.new(batch_size: self.class.batch_size)
  end

  def finish_success
    csv_import.update!(
      status: "succeeded",
      finished_at: Time.current,
      error_rows: [],
      imported_count: imported_count,
      failed_count: 0
    )
    BackfillSettlementsJob.perform_later
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
