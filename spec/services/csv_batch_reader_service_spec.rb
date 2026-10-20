require "rails_helper"

RSpec.describe CsvBatchReaderService do
  it "yields data rows in batches, counting the header as line 1" do
    io = StringIO.new(<<~CSV)
      id;reference
      one;a
      two;b
      three;c
    CSV

    batches = []
    described_class.each(io:, batch_size: 2) { |batch| batches << batch }

    expect(batches.map { |batch| batch.map { |row, line| [ row["id"], line ] } }).to eq([
      [ [ "one", 2 ], [ "two", 3 ] ],
      [ [ "three", 4 ] ]
    ])
  end
end
