class ImportCsv::Orders
  include ImportCsv::CsvRow

  COLUMNS = {
    external_id: "id",
    merchant: "merchant_reference",
    ordered_on: "created_at",
    amount_cents: "amount",
    commission_cents: "amount"
  }.freeze

  def import(row, line_number)
    reference = value(row, "merchant_reference", line_number)
    merchant = Merchant.find_by(reference: reference)
    raise ImportCsv::RowError.new(line_number, "merchant_reference", "is unknown") if merchant.nil?

    amount_cents = money_value(row, "amount", line_number)
    order = Order.find_or_initialize_by(external_id: value(row, "id", line_number))
    order.assign_attributes(
      merchant: merchant,
      ordered_on: date_value(row, "created_at", line_number),
      amount_cents: amount_cents,
      commission_cents: Commission.cents_for(amount_cents)
    )
    save_record!(order, line_number, COLUMNS)
  end
end
