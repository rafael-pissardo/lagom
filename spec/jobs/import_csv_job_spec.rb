require "rails_helper"

RSpec.describe ImportCsvJob do
  it "delegates to ImportCsvService" do
    csv_import = create(:csv_import)
    expect(ImportCsvService).to receive(:call).with(csv_import: csv_import)

    described_class.perform_now(csv_import.id)
  end
end
