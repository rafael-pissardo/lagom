require "rails_helper"

RSpec.describe ImportCsv do
  def store_csv(csv_import, content)
    files[csv_import.object_key] = content
  end

  let(:files) { {} }

  before do
    allow(Bucket).to receive(:open) do |key, &block|
      block.call(StringIO.new(files.fetch(key)))
    end
  end

  it "defaults the batch size to 500" do
    previous = ENV.delete("CSV_IMPORT_BATCH_SIZE")
    expect(described_class.batch_size).to eq(500)
  ensure
    ENV["CSV_IMPORT_BATCH_SIZE"] = previous if previous
  end

  it "imports every merchant when the batch size is smaller than the file and enqueues backfill" do
    previous = ENV["CSV_IMPORT_BATCH_SIZE"]
    ENV["CSV_IMPORT_BATCH_SIZE"] = "1"
    csv_import = create(:csv_import, kind: "merchants", status: "pending")
    store_csv(csv_import, <<~CSV)
      id;reference;email;live_on;disbursement_frequency;minimum_monthly_fee
      86312006-4d7e-45c4-9c28-788f4aa68a62;padberg_group;info@padberg-group.com;2023-02-01;DAILY;0.0
      11111111-1111-4111-8111-111111111111;other_group;info@other.test;2023-02-01;WEEKLY;15.0
    CSV
    expect(CsvBatchReader).to receive(:each).with(io: kind_of(StringIO), batch_size: 1).twice.and_call_original

    expect {
      described_class.call(csv_import: csv_import)
    }.to have_enqueued_job(BackfillSettlementsJob)

    csv_import.reload
    expect(csv_import).to be_succeeded
    expect(csv_import).to be_merchants
    expect(csv_import.merchants_imported_count).to eq(2)
    expect(Merchant.find_by!(reference: "other_group").minimum_monthly_fee_cents).to eq(1_500)
  ensure
    previous ? ENV["CSV_IMPORT_BATCH_SIZE"] = previous : ENV.delete("CSV_IMPORT_BATCH_SIZE")
  end

  it "rolls back every merchant when one row has an error and stores line and column" do
    csv_import = create(:csv_import, kind: "merchants")
    store_csv(csv_import, <<~CSV)
      id;reference;email;live_on;disbursement_frequency;minimum_monthly_fee
      86312006-4d7e-45c4-9c28-788f4aa68a62;padberg_group;info@padberg-group.com;2023-02-01;DAILY;0.0
      22222222-2222-4222-8222-222222222222;broken_group;;2023-02-01;DAILY;0.0
    CSV

    expect {
      described_class.call(csv_import: csv_import)
    }.not_to have_enqueued_job(BackfillSettlementsJob)

    csv_import.reload
    expect(csv_import).to be_failed
    expect(csv_import.merchants_imported_count).to eq(0)
    expect(Merchant.find_by(reference: "padberg_group")).to be_nil
    expect(csv_import.error_rows).to eq([
      { "line" => 3, "column" => "email", "message" => "is blank" }
    ])
    expect(csv_import.errors_txt).to eq("line 3, column email: is blank\n")
  end

  it "imports orders for an existing merchant and enqueues backfill" do
    create(:merchant, reference: "padberg_group", live_on: Date.new(2023, 2, 1))
    csv_import = create(:csv_import, kind: "orders")
    store_csv(csv_import, <<~CSV)
      id;merchant_reference;amount;created_at
      e653f3e14bc4;padberg_group;102.29;2023-02-01
    CSV

    expect {
      described_class.call(csv_import: csv_import)
    }.to have_enqueued_job(BackfillSettlementsJob)

    csv_import.reload
    expect(csv_import).to be_succeeded
    expect(csv_import.orders_imported_count).to eq(1)
    expect(Order.find_by!(external_id: "e653f3e14bc4").commission_cents).to eq(98)
  end

  it "rolls back every order when one row has an error and records the column" do
    create(:merchant, reference: "padberg_group", live_on: Date.new(2023, 2, 1))
    csv_import = create(:csv_import, kind: "orders")
    store_csv(csv_import, <<~CSV)
      id;merchant_reference;amount;created_at
      e653f3e14bc4;padberg_group;102.29;2023-02-01
      badrow;unknown_merchant;10.00;2023-02-01
      early;padberg_group;10.00;2022-01-01
      negative;padberg_group;-1.00;2023-02-01
    CSV

    described_class.call(csv_import: csv_import)

    csv_import.reload
    expect(csv_import).to be_failed
    expect(Order.count).to eq(0)
    expect(csv_import.error_rows).to eq([
      { "line" => 3, "column" => "merchant_reference", "message" => "is unknown" },
      { "line" => 4, "column" => "created_at", "message" => "Ordered on cannot be before the merchant live_on date" },
      { "line" => 5, "column" => "amount", "message" => "is negative" }
    ])
  end

  it "looks up a repeated merchant once and upserts the orders without reading them" do
    previous = ENV["CSV_IMPORT_BATCH_SIZE"]
    ENV["CSV_IMPORT_BATCH_SIZE"] = "1"
    create(:merchant, reference: "padberg_group", live_on: Date.new(2023, 2, 1))
    csv_import = create(:csv_import, kind: "orders")
    store_csv(csv_import, <<~CSV)
      id;merchant_reference;amount;created_at
      e653f3e14bc4;padberg_group;102.29;2023-02-01
      aaaaaaaaaaaa;padberg_group;50.00;2023-02-02
    CSV

    queries = capture_sql { described_class.call(csv_import: csv_import) }

    expect(selects(queries, "merchants")).to eq(1)
    expect(selects(queries, "orders")).to eq(0)
    expect(upserts(queries, "orders")).to eq(2)
    expect(Order.count).to eq(2)
  ensure
    previous ? ENV["CSV_IMPORT_BATCH_SIZE"] = previous : ENV.delete("CSV_IMPORT_BATCH_SIZE")
  end

  it "upserts merchants without loading each id and keeps created_at on update" do
    merchant = create(
      :merchant,
      id: "86312006-4d7e-45c4-9c28-788f4aa68a62",
      reference: "padberg_group",
      email: "old@padberg.test",
      live_on: Date.new(2023, 2, 1),
      disbursement_frequency: "DAILY",
      minimum_monthly_fee_cents: 0
    )
    created_at = merchant.created_at
    csv_import = create(:csv_import, kind: "merchants")
    store_csv(csv_import, <<~CSV)
      id;reference;email;live_on;disbursement_frequency;minimum_monthly_fee
      86312006-4d7e-45c4-9c28-788f4aa68a62;padberg_group;info@padberg-group.com;2023-02-01;DAILY;0.0
      11111111-1111-4111-8111-111111111111;other_group;info@other.test;2023-02-01;WEEKLY;15.0
    CSV

    queries = capture_sql { described_class.call(csv_import: csv_import) }

    expect(queries.grep(/"merchants"\."id"/)).to be_empty
    expect(upserts(queries, "merchants")).to eq(1)
    expect(merchant.reload.email).to eq("info@padberg-group.com")
    expect(merchant.created_at).to eq(created_at)
    expect(Merchant.find_by!(reference: "other_group").minimum_monthly_fee_cents).to eq(1_500)
  end

  it "rejects a reference owned by another merchant and writes nothing" do
    create(:merchant, id: "86312006-4d7e-45c4-9c28-788f4aa68a62", reference: "padberg_group")
    csv_import = create(:csv_import, kind: "merchants")
    store_csv(csv_import, <<~CSV)
      id;reference;email;live_on;disbursement_frequency;minimum_monthly_fee
      11111111-1111-4111-8111-111111111111;padberg_group;info@other.test;2023-02-01;DAILY;0.0
    CSV

    described_class.call(csv_import: csv_import)

    csv_import.reload
    expect(csv_import).to be_failed
    expect(Merchant.where(id: "11111111-1111-4111-8111-111111111111")).to be_none
    expect(csv_import.error_rows).to eq([
      { "line" => 2, "column" => "reference", "message" => "Reference has already been taken" }
    ])
  end

  it "rejects a reference repeated in the file and writes nothing" do
    csv_import = create(:csv_import, kind: "merchants")
    store_csv(csv_import, <<~CSV)
      id;reference;email;live_on;disbursement_frequency;minimum_monthly_fee
      86312006-4d7e-45c4-9c28-788f4aa68a62;padberg_group;info@padberg-group.com;2023-02-01;DAILY;0.0
      11111111-1111-4111-8111-111111111111;padberg_group;info@other.test;2023-02-01;WEEKLY;15.0
    CSV

    described_class.call(csv_import: csv_import)

    csv_import.reload
    expect(csv_import).to be_failed
    expect(Merchant.count).to eq(0)
    expect(csv_import.error_rows).to eq([
      { "line" => 3, "column" => "reference", "message" => "Reference has already been taken" }
    ])
  end

  it "keeps the last order when the same id is repeated in one batch" do
    create(:merchant, reference: "padberg_group", live_on: Date.new(2023, 2, 1))
    csv_import = create(:csv_import, kind: "orders")
    store_csv(csv_import, <<~CSV)
      id;merchant_reference;amount;created_at
      e653f3e14bc4;padberg_group;10.00;2023-02-01
      e653f3e14bc4;padberg_group;102.29;2023-02-01
    CSV

    described_class.call(csv_import: csv_import)

    order = Order.find_by!(external_id: "e653f3e14bc4")
    expect(Order.count).to eq(1)
    expect(order.amount_cents).to eq(10_229)
    expect(order.commission_cents).to eq(98)
  end

  it "updates an order in place and keeps its disbursement" do
    merchant = create(:merchant, reference: "padberg_group", live_on: Date.new(2023, 2, 1))
    disbursement = create(:disbursement, merchant: merchant)
    order = create(
      :order,
      merchant: merchant,
      disbursement: disbursement,
      external_id: "e653f3e14bc4",
      ordered_on: Date.new(2023, 2, 1),
      amount_cents: 1_000,
      commission_cents: 10
    )
    csv_import = create(:csv_import, kind: "orders")
    store_csv(csv_import, <<~CSV)
      id;merchant_reference;amount;created_at
      e653f3e14bc4;padberg_group;102.29;2023-02-01
    CSV

    described_class.call(csv_import: csv_import)

    order.reload
    expect(order.disbursement_id).to eq(disbursement.id)
    expect(order.amount_cents).to eq(10_229)
    expect(order.commission_cents).to eq(98)
    expect(Order.count).to eq(1)
  end

  def capture_sql
    queries = []
    callback = ->(*, payload) { queries << payload[:sql] }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
    queries
  end

  def selects(queries, table)
    queries.count { |sql| sql.start_with?("SELECT") && sql.include?(%("#{table}")) }
  end

  def upserts(queries, table)
    queries.count { |sql| sql.start_with?("INSERT") && sql.include?(%("#{table}")) && sql.include?("ON CONFLICT") }
  end
end
