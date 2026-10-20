require "csv"

class CsvBatchReaderService
  def self.each(io:, batch_size:)
    CSV.new(io, headers: true, col_sep: ";")
      .each_with_index
      .lazy
      .map { |row, index| [ row, index + 2 ] }
      .each_slice(batch_size) { |batch| yield batch }
  end
end
