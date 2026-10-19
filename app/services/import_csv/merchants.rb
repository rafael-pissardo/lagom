class ImportCsv::Merchants
  include ImportCsv::CsvRow

  COLUMNS = {
    id: "id",
    reference: "reference",
    email: "email",
    live_on: "live_on",
    disbursement_frequency: "disbursement_frequency",
    minimum_monthly_fee_cents: "minimum_monthly_fee"
  }.freeze

  def import(row, line_number)
    merchant = Merchant.find_or_initialize_by(id: value(row, "id", line_number))
    merchant.assign_attributes(
      reference: value(row, "reference", line_number),
      email: value(row, "email", line_number),
      live_on: date_value(row, "live_on", line_number),
      disbursement_frequency: value(row, "disbursement_frequency", line_number),
      minimum_monthly_fee_cents: money_value(row, "minimum_monthly_fee", line_number)
    )
    save_record!(merchant, line_number, COLUMNS)
  rescue ActiveRecord::StatementInvalid
    raise ImportCsv::RowError.new(line_number, "id", "is invalid")
  end
end
