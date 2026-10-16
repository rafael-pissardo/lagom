require "csv"

class ImportCsv
  MAX_STORED_ERRORS = 50

  def self.call(csv_import:)
    new(csv_import:).call
  end

  def initialize(csv_import:)
    @csv_import = csv_import
    @error_rows = []
  end

  def call
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

    merchants_by_reference = import_merchants
    import_orders(merchants_by_reference)

    csv_import.update!(
      status: "succeeded",
      finished_at: Time.current,
      error_rows: error_rows
    )

    BackfillSettlementsJob.perform_later
  rescue StandardError => error
    csv_import.update!(
      status: "failed",
      finished_at: Time.current,
      error_message: error.message,
      error_rows: error_rows
    )
    raise
  end

  private

  attr_reader :csv_import, :error_rows

  def import_merchants
    by_reference = {}
    imported = 0
    failed = 0

    each_row(csv_import.merchants_file, "merchants") do |row, line_number|
      merchant = Merchant.find_or_initialize_by(id: row.fetch("id"))
      merchant.assign_attributes(
        reference: row.fetch("reference"),
        email: row.fetch("email"),
        live_on: Date.iso8601(row.fetch("live_on")),
        disbursement_frequency: row.fetch("disbursement_frequency"),
        minimum_monthly_fee_cents: Finance::Amount.from_decimal_string(row.fetch("minimum_monthly_fee"))
      )
      merchant.save!
      by_reference[merchant.reference] = merchant
      imported += 1
    rescue StandardError => error
      failed += 1
      store_error(file: "merchants", line: line_number, message: error.message)
    end

    csv_import.update!(
      merchants_imported_count: imported,
      merchants_failed_count: failed
    )

    by_reference
  end

  def import_orders(merchants_by_reference)
    imported = 0
    failed = 0

    each_row(csv_import.orders_file, "orders") do |row, line_number|
      merchant = merchants_by_reference[row.fetch("merchant_reference")] ||
        Merchant.find_by(reference: row.fetch("merchant_reference"))
      raise ArgumentError, "unknown merchant" if merchant.nil?

      ordered_on = Date.iso8601(row.fetch("created_at"))
      raise ArgumentError, "ordered before live_on" if ordered_on < merchant.live_on

      amount_cents = Finance::Amount.from_decimal_string(row.fetch("amount"))
      raise ArgumentError, "amount is negative" if amount_cents.negative?

      order = Order.find_or_initialize_by(external_id: row.fetch("id"))
      order.assign_attributes(
        merchant: merchant,
        ordered_on: ordered_on,
        amount_cents: amount_cents,
        commission_cents: Commission.cents_for(amount_cents)
      )
      order.save!
      imported += 1
    rescue StandardError => error
      failed += 1
      store_error(file: "orders", line: line_number, message: error.message)
    end

    csv_import.update!(
      orders_imported_count: imported,
      orders_failed_count: failed
    )
  end

  def each_row(attachment, label)
    raise ArgumentError, "#{label} file is missing" unless attachment.attached?

    attachment.open do |file|
      CSV.foreach(file.path, headers: true, col_sep: ";").with_index(2) do |row, line_number|
        yield row, line_number
      end
    end
  end

  def store_error(file:, line:, message:)
    return if error_rows.size >= MAX_STORED_ERRORS

    error_rows << { "file" => file, "line" => line, "message" => message }
  end
end
