require "rails_helper"

RSpec.describe ImportCsvJob do
  it "delegates to ImportCsv" do
    csv_import = create(:csv_import)
    expect(ImportCsv).to receive(:call).with(csv_import: csv_import)

    described_class.perform_now(csv_import.id)
  end
end
