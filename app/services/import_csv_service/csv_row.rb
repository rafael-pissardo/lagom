module ImportCsvService::CsvRow
  private

  def last_entries(entries, key)
    entries.reverse.uniq { |_line, attrs| attrs.fetch(key) }.reverse
  end

  def row_error(error)
    { "line" => error.line, "column" => error.column, "message" => error.message }
  end

  def raise_row_error!(record, line_number, columns)
    attribute = record.errors.attribute_names.find { |name| name != :base } || :base
    column = columns.fetch(attribute, attribute.to_s)
    raise ImportCsvService::RowError.new(line_number, column, record.errors.full_messages.first)
  end

  def value(row, column, line_number)
    cell = row[column]
    raise ImportCsvService::RowError.new(line_number, column, "is blank") if cell.nil? || cell.strip.empty?

    cell.strip
  end

  def date_value(row, column, line_number)
    Date.iso8601(value(row, column, line_number))
  rescue Date::Error, ArgumentError
    raise ImportCsvService::RowError.new(line_number, column, "is invalid")
  end

  def money_value(row, column, line_number)
    cents = Finance::Amount.from_decimal_string(value(row, column, line_number))
    raise ImportCsvService::RowError.new(line_number, column, "is negative") if cents.negative?

    cents
  rescue ArgumentError
    raise ImportCsvService::RowError.new(line_number, column, "is invalid")
  end
end
