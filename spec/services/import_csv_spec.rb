require "rails_helper"

RSpec.describe ImportCsv do
  def attach_csv(csv_import, name, content)
    csv_import.public_send(name).attach(
      io: StringIO.new(content),
      filename: "#{name}.csv",
      content_type: "text/csv"
    )
  end

  it "imports valid rows, skips invalid ones, and enqueues backfill" do
    csv_import = create(:csv_import)
    attach_csv(
      csv_import,
      :merchants_file,
      <<~CSV
        id;reference;email;live_on;disbursement_frequency;minimum_monthly_fee
        86312006-4d7e-45c4-9c28-788f4aa68a62;padberg_group;info@padberg-group.com;2023-02-01;DAILY;0.0
      CSV
    )
    attach_csv(
      csv_import,
      :orders_file,
      <<~CSV
        id;merchant_reference;amount;created_at
        e653f3e14bc4;padberg_group;102.29;2023-02-01
        badrow;unknown_merchant;10.00;2023-02-01
        early;padberg_group;10.00;2022-01-01
      CSV
    )

    expect {
      described_class.call(csv_import: csv_import)
    }.to have_enqueued_job(BackfillSettlementsJob)

    csv_import.reload
    expect(csv_import).to be_succeeded
    expect(csv_import.merchants_imported_count).to eq(1)
    expect(csv_import.orders_imported_count).to eq(1)
    expect(csv_import.orders_failed_count).to eq(2)
    expect(Order.find_by!(external_id: "e653f3e14bc4").commission_cents).to eq(98)
  end
end
