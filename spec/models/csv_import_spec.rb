require "rails_helper"

RSpec.describe CsvImport do
  it "answers kind predicates from the enum" do
    expect(build(:csv_import, kind: "merchants")).to be_merchants
    expect(build(:csv_import, kind: "orders")).to be_orders
  end

  it {
    is_expected.to define_enum_for(:status)
      .with_values(pending: "pending", processing: "processing", succeeded: "succeeded", failed: "failed")
      .backed_by_column_of_type(:string)
      .with_default(:pending)
      .validating
  }

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
