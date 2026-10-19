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

  it "pushes the rendered status to the import's stream when the status changes" do
    csv_import = create(:csv_import, status: "processing", kind: "orders")

    expect {
      csv_import.update!(status: "succeeded", imported_count: 7)
    }.to have_broadcasted_to(csv_import.to_gid_param).with { |html|
      doc = Nokogiri::HTML.fragment(html)
      stream = doc.at_css("turbo-stream")
      expect(stream["action"]).to eq("replace")
      expect(stream["target"]).to eq("status_csv_import_#{csv_import.id}")
      expect(stream.text).to include("succeeded").and include("7").and include("Import finished")
    }
  end

  it "does not broadcast when nothing but the counters change" do
    csv_import = create(:csv_import, status: "processing")

    expect {
      csv_import.update!(imported_count: 3)
    }.not_to have_broadcasted_to(csv_import.to_gid_param)
  end

  it "names the stored object with the kind and a UTC timestamp" do
    now = Time.utc(2026, 10, 19, 11, 21, 3, 45_000)

    expect(described_class.object_key_for("orders", now: now)).to eq("orders-20261019112103045.csv")
  end
end
