require "rails_helper"

RSpec.describe CsvImport do
  it "exposes status helpers" do
    expect(build(:csv_import, status: "pending")).to be_pending
    expect(build(:csv_import, status: "processing")).to be_processing
    expect(build(:csv_import, status: "succeeded")).to be_succeeded
    expect(build(:csv_import, status: "failed")).to be_failed
  end
end
