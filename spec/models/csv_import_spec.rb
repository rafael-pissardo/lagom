require "rails_helper"

RSpec.describe CsvImport do
  it "exposes status helpers" do
    expect(build(:csv_import, status: "pending")).to be_pending
    expect(build(:csv_import, status: "processing")).to be_processing
    expect(build(:csv_import, status: "succeeded")).to be_succeeded
    expect(build(:csv_import, status: "failed")).to be_failed
  end

  it "names the stored object with the kind and a UTC timestamp" do
    now = Time.utc(2026, 10, 19, 11, 21, 3, 45_000)

    expect(described_class.object_key_for("orders", now: now)).to eq("orders-20261019112103045.csv")
  end
end
