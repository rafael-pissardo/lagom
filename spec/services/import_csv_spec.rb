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
    phases = []
    allow(ActiveRecord::Base).to receive(:transaction).and_wrap_original do |method, *args, **kwargs, &block|
      phases << :write if kwargs[:requires_new]
      method.call(*args, **kwargs, &block)
    end
    expect(CsvBatchReader).to receive(:each).with(io: kind_of(StringIO), batch_size: 1).twice.and_wrap_original do |method, **kwargs, &block|
      phases << (phases.include?(:write) ? :read_inside : :read_outside)
      method.call(**kwargs, &block)
    end

    expect {
      described_class.call(csv_import: csv_import)
    }.to have_enqueued_job(BackfillSettlementsJob)

    expect(phases).to eq(%i[read_outside write read_inside])

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

    phases = []
    allow(ActiveRecord::Base).to receive(:transaction).and_wrap_original do |method, *args, **kwargs, &block|
      phases << :write if kwargs[:requires_new]
      method.call(*args, **kwargs, &block)
    end

    expect {
      described_class.call(csv_import: csv_import)
    }.not_to have_enqueued_job(BackfillSettlementsJob)

    expect(phases).to eq([])

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

    expect(queries.count { |sql| sql.include?("LIMIT") && sql.include?('"merchants"') }).to eq(1)
    expect(queries.count { |sql| sql.include?("FOR UPDATE") && sql.include?('"merchants"') }).to eq(1)
    expect(selects(queries, "orders")).to eq(0)
    expect(upserts(queries, "orders")).to eq(2)
    expect(queries.grep(/\AINSERT/).grep(/"orders"/)).to all(satisfy { |sql| !sql.include?("RETURNING") })
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

    expect(queries.grep(/"merchants"\."id" = /).grep_v(/FOR UPDATE/)).to be_empty
    expect(queries.count { |sql| sql.include?('"merchants"."reference" IN') }).to eq(3)
    expect(queries.count { |sql| sql.include?('"merchants"."id" IN') }).to eq(3)
    expect(queries.count { |sql| sql.include?("FOR UPDATE") && sql.include?('"merchants"') }).to eq(1)
    expect(upserts(queries, "merchants")).to eq(1)
    expect(queries.grep(/\AINSERT/).grep(/"merchants"/)).to all(satisfy { |sql| !sql.include?("RETURNING") })
    expect(merchant.reload.email).to eq("info@padberg-group.com")
    expect(merchant.created_at).to eq(created_at)
    expect(Merchant.find_by!(reference: "other_group").minimum_monthly_fee_cents).to eq(1_500)
  end

  it "loads distinct merchant references and ids in batches" do
    previous = ENV["CSV_IMPORT_BATCH_SIZE"]
    ENV["CSV_IMPORT_BATCH_SIZE"] = "2"
    csv_import = create(:csv_import, kind: "merchants")
    store_csv(csv_import, <<~CSV)
      id;reference;email;live_on;disbursement_frequency;minimum_monthly_fee
      86312006-4d7e-45c4-9c28-788f4aa68a62;padberg_group;info@padberg-group.com;2023-02-01;DAILY;0.0
      11111111-1111-4111-8111-111111111111;other_group;info@other.test;2023-02-01;WEEKLY;15.0
      22222222-2222-4222-8222-222222222222;third_group;info@third.test;2023-02-01;DAILY;0.0
    CSV

    queries = capture_sql { described_class.call(csv_import: csv_import) }

    expect(selects(queries, "merchants")).to eq(12)
    expect(queries.none? { |sql| sql.include?("LIMIT") && sql.include?('"merchants"') }).to be true
    expect(Merchant.count).to eq(3)
  ensure
    previous ? ENV["CSV_IMPORT_BATCH_SIZE"] = previous : ENV.delete("CSV_IMPORT_BATCH_SIZE")
  end

  it "lets a later row take merchant_old after an existing id moves to merchant_new" do
    existing_id = "86312006-4d7e-45c4-9c28-788f4aa68a62"
    new_id = "11111111-1111-4111-8111-111111111111"
    create(:merchant, id: existing_id, reference: "merchant_old", email: "old@merchant.test", live_on: Date.new(2023, 2, 1))
    csv_import = create(:csv_import, kind: "merchants")
    store_csv(csv_import, <<~CSV)
      id;reference;email;live_on;disbursement_frequency;minimum_monthly_fee
      #{existing_id};merchant_new;info@merchant-new.test;2023-02-01;DAILY;0.0
      #{new_id};merchant_old;info@merchant-old.test;2023-02-01;WEEKLY;15.0
    CSV

    described_class.call(csv_import: csv_import)

    csv_import.reload
    expect(csv_import).to be_succeeded
    expect(Merchant.find(existing_id).reference).to eq("merchant_new")
    expect(Merchant.find(new_id).reference).to eq("merchant_old")
  end

  it "rejects a reference taken after validation and writes nothing" do
    csv_import = create(:csv_import, kind: "merchants")
    store_csv(csv_import, <<~CSV)
      id;reference;email;live_on;disbursement_frequency;minimum_monthly_fee
      11111111-1111-4111-8111-111111111111;padberg_group;info@other.test;2023-02-01;DAILY;0.0
    CSV
    allow_any_instance_of(ImportCsv::MerchantCache).to receive(:lock_existing).and_wrap_original do |method, **kwargs|
      create(:merchant, reference: "padberg_group")
      method.call(**kwargs)
    end

    described_class.call(csv_import: csv_import)

    csv_import.reload
    expect(csv_import).to be_failed
    expect(Merchant.count).to eq(0)
    expect(csv_import.error_rows).to eq([
      { "line" => 2, "column" => "reference", "message" => "Reference has already been taken" }
    ])
  end

  it "rejects an order when the merchant live_on moves after validation and writes nothing" do
    merchant = create(:merchant, reference: "padberg_group", live_on: Date.new(2023, 2, 1))
    csv_import = create(:csv_import, kind: "orders")
    store_csv(csv_import, <<~CSV)
      id;merchant_reference;amount;created_at
      e653f3e14bc4;padberg_group;102.29;2023-02-01
    CSV
    allow_any_instance_of(ImportCsv::MerchantCache).to receive(:lock_existing).and_wrap_original do |method, **kwargs|
      merchant.update!(live_on: Date.new(2023, 3, 1))
      method.call(**kwargs)
    end

    described_class.call(csv_import: csv_import)

    csv_import.reload
    expect(csv_import).to be_failed
    expect(Order.count).to eq(0)
    expect(merchant.reload.live_on).to eq(Date.new(2023, 2, 1))
    expect(csv_import.error_rows).to eq([
      { "line" => 2, "column" => "created_at", "message" => "Ordered on cannot be before the merchant live_on date" }
    ])
  end

  it "rejects a merchant id that is not a uuid and writes nothing" do
    csv_import = create(:csv_import, kind: "merchants")
    store_csv(csv_import, <<~CSV)
      id;reference;email;live_on;disbursement_frequency;minimum_monthly_fee
      not-a-uuid;padberg_group;info@padberg-group.com;2023-02-01;DAILY;0.0
    CSV

    described_class.call(csv_import: csv_import)

    csv_import.reload
    expect(csv_import).to be_failed
    expect(Merchant.count).to eq(0)
    expect(csv_import.error_rows).to eq([
      { "line" => 2, "column" => "id", "message" => "is invalid" }
    ])
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
    queries.count { |sql| sql.include?(%(FROM "#{table}")) }
  end

  def upserts(queries, table)
    queries.count { |sql| sql.start_with?("INSERT") && sql.include?(%("#{table}")) && sql.include?("ON CONFLICT") }
  end
end
