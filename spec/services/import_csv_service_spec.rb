require "rails_helper"

RSpec.describe ImportCsvService do
  def store_csv(csv_import, content)
    files[csv_import.object_key] = content
  end

  let(:files) { {} }
  let(:bucket_opens) { [] }
  let(:bucket_rewinds) { [] }

  before do
    allow(BucketService).to receive(:open) do |key, &block|
      bucket_opens << key
      io = StringIO.new(files.fetch(key))
      rewinds = bucket_rewinds
      io.define_singleton_method(:rewind) do
        rewinds << key
        super()
      end
      block.call(io)
    end
  end

  it "defaults the batch size to 500" do
    previous = ENV.delete("CSV_IMPORT_BATCH_SIZE")
    expect(described_class.batch_size).to eq(500)
  ensure
    ENV["CSV_IMPORT_BATCH_SIZE"] = previous if previous
  end

  it "imports every merchant when the batch size is smaller than the file and does not enqueue a settlement" do
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
    expect(CsvBatchReaderService).to receive(:each).with(io: kind_of(described_class::Stream), batch_size: 1).twice.and_wrap_original do |method, **kwargs, &block|
      phases << (phases.include?(:write) ? :read_inside : :read_outside)
      method.call(**kwargs, &block)
    end

    expect {
      described_class.call(csv_import: csv_import)
    }.not_to have_enqueued_job

    expect(phases).to eq(%i[read_outside write read_inside])
    expect(bucket_opens).to eq([ csv_import.object_key ])
    expect(bucket_rewinds).to eq([ csv_import.object_key, csv_import.object_key ])

    csv_import.reload
    expect(csv_import).to be_succeeded
    expect(csv_import).to be_merchants
    expect(csv_import.imported_count).to eq(2)
    expect(csv_import.failed_count).to eq(0)
    expect(Merchant.find_by!(reference: "other_group").minimum_monthly_fee_cents).to eq(1_500)
  ensure
    previous ? ENV["CSV_IMPORT_BATCH_SIZE"] = previous : ENV.delete("CSV_IMPORT_BATCH_SIZE")
  end

  it "validates and writes a file larger than one batch without reading it into one string" do
    previous = ENV["CSV_IMPORT_BATCH_SIZE"]
    ENV["CSV_IMPORT_BATCH_SIZE"] = "1"
    body = + "id;reference;email;live_on;disbursement_frequency;minimum_monthly_fee\n"
    200.times do |index|
      body << format("%08x-0000-4000-8000-%012x", index + 1, index + 1)
      body << ";shop_#{index};shop_#{index}@test.dev;2023-02-01;DAILY;0.0\n"
    end
    csv_import = create(:csv_import, kind: "merchants", status: "pending")
    largest_read = 0
    allow(BucketService).to receive(:open) do |_key, &block|
      io = StringIO.new(body)
      io.define_singleton_method(:read) do |*args, **kwargs, &read_block|
        raise "unbounded read" if args.empty? || args.first.nil?

        chunk = super(*args, **kwargs, &read_block)
        largest_read = chunk.bytesize if chunk && chunk.bytesize > largest_read
        chunk
      end
      io.define_singleton_method(:gets) do |*args, **kwargs, &gets_block|
        chunk = super(*args, **kwargs, &gets_block)
        largest_read = chunk.bytesize if chunk && chunk.bytesize > largest_read
        chunk
      end
      block.call(io)
    end

    described_class.call(csv_import: csv_import)

    expect(csv_import.reload).to be_succeeded
    expect(csv_import.imported_count).to eq(200)
    expect(Merchant.count).to eq(200)
    expect(largest_read).to be < body.bytesize
    expect(largest_read).to be <= 8 * 1024
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
    }.not_to have_enqueued_job

    expect(phases).to eq([])
    expect(bucket_opens).to eq([ csv_import.object_key ])
    expect(bucket_rewinds).to eq([ csv_import.object_key ])

    csv_import.reload
    expect(csv_import).to be_failed
    expect(csv_import.imported_count).to eq(0)
    expect(csv_import.failed_count).to eq(1)
    expect(Merchant.find_by(reference: "padberg_group")).to be_nil
    expect(csv_import.error_rows).to eq([
      { "line" => 3, "column" => "email", "message" => "is blank" }
    ])
    expect(csv_import.errors_txt).to eq("line 3, column email: is blank\n")
  end

  it "imports orders for an existing merchant and does not enqueue a settlement" do
    create(:merchant, reference: "padberg_group", live_on: Date.new(2023, 2, 1))
    csv_import = create(:csv_import, kind: "orders")
    store_csv(csv_import, <<~CSV)
      id;merchant_reference;amount;created_at
      e653f3e14bc4;padberg_group;102.29;2023-02-01
    CSV

    expect {
      described_class.call(csv_import: csv_import)
    }.not_to have_enqueued_job

    csv_import.reload
    expect(csv_import).to be_succeeded
    expect(csv_import.imported_count).to eq(1)
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

  it "looks up a repeated merchant once and reads orders once per batch" do
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

    expect(selects(queries, "merchants")).to eq(2)
    expect(queries.none? { |sql| sql.include?("LIMIT") && sql.include?('"merchants"') }).to be true
    expect(queries.none? { |sql| sql.include?("FOR UPDATE") && sql.include?('"merchants"') }).to be true
    expect(selects(queries, "orders")).to eq(4)
    expect(queries.count { |sql| sql.include?("FOR UPDATE") && sql.include?('"orders"') }).to eq(2)
    expect(queries.count { |sql| sql.include?("pg_advisory_xact_lock") }).to eq(1)
    expect(upserts(queries, "orders")).to eq(0)
    expect(queries.count { |sql| sql.start_with?("INSERT") && sql.include?('"orders"') }).to eq(2)
    expect(queries.grep(/\AINSERT/).grep(/"orders"/)).to all(satisfy { |sql| !sql.include?("RETURNING") })
    expect(Order.count).to eq(2)
  ensure
    previous ? ENV["CSV_IMPORT_BATCH_SIZE"] = previous : ENV.delete("CSV_IMPORT_BATCH_SIZE")
  end

  it "fails the import when a merchant id was already processed and writes nothing else" do
    merchant = create(
      :merchant,
      id: "86312006-4d7e-45c4-9c28-788f4aa68a62",
      reference: "padberg_group",
      email: "old@padberg.test",
      live_on: Date.new(2023, 2, 1),
      disbursement_frequency: "DAILY",
      minimum_monthly_fee_cents: 0
    )
    csv_import = create(:csv_import, kind: "merchants")
    store_csv(csv_import, <<~CSV)
      id;reference;email;live_on;disbursement_frequency;minimum_monthly_fee
      86312006-4d7e-45c4-9c28-788f4aa68a62;padberg_group;info@padberg-group.com;2023-02-01;DAILY;0.0
      11111111-1111-4111-8111-111111111111;other_group;info@other.test;2023-02-01;WEEKLY;15.0
    CSV

    expect {
      described_class.call(csv_import: csv_import)
    }.not_to have_enqueued_job

    csv_import.reload
    expect(csv_import).to be_failed
    expect(csv_import.imported_count).to eq(0)
    expect(merchant.reload.email).to eq("old@padberg.test")
    expect(Merchant.find_by(reference: "other_group")).to be_nil
    expect(csv_import.error_rows).to eq([
      already_processed_error(2)
    ])
    expect(csv_import.errors_txt).to eq("#{already_processed_line(2)}\n")
  end

  it "fails a repeated merchants file and records each processed line" do
    csv = <<~CSV
      id;reference;email;live_on;disbursement_frequency;minimum_monthly_fee
      86312006-4d7e-45c4-9c28-788f4aa68a62;padberg_group;info@padberg-group.com;2023-02-01;DAILY;0.0
      11111111-1111-4111-8111-111111111111;other_group;info@other.test;2023-02-01;WEEKLY;15.0
    CSV
    first = create(:csv_import, kind: "merchants")
    store_csv(first, csv)
    described_class.call(csv_import: first)
    expect(first.reload).to be_succeeded

    second = create(:csv_import, kind: "merchants")
    store_csv(second, csv)

    expect {
      described_class.call(csv_import: second)
    }.not_to have_enqueued_job

    expect(second.reload).to be_failed
    expect(Merchant.count).to eq(2)
    expect(Merchant.find("86312006-4d7e-45c4-9c28-788f4aa68a62").email).to eq("info@padberg-group.com")
    expect(second.error_rows).to eq([ already_processed_error(2), already_processed_error(3) ])
    expect(second.errors_txt).to eq("#{already_processed_line(2)}\n#{already_processed_line(3)}\n")
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

    expect(selects(queries, "merchants")).to eq(8)
    expect(queries.none? { |sql| sql.include?("LIMIT") && sql.include?('"merchants"') }).to be true
    expect(queries.none? { |sql| sql.include?("FOR UPDATE") && sql.include?('"merchants"') }).to be true
    expect(queries.count { |sql| sql.include?("pg_advisory_xact_lock") }).to eq(1)
    expect(upserts(queries, "merchants")).to eq(0)
    expect(queries.count { |sql| sql.start_with?("INSERT") && sql.include?('"merchants"') }).to eq(2)
    expect(queries.grep(/\AINSERT/).grep(/"merchants"/)).to all(satisfy { |sql| !sql.include?("RETURNING") })
    expect(Merchant.count).to eq(3)
  ensure
    previous ? ENV["CSV_IMPORT_BATCH_SIZE"] = previous : ENV.delete("CSV_IMPORT_BATCH_SIZE")
  end

  it "fails when an already processed merchant would hand its reference to a new row" do
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
    expect(csv_import).to be_failed
    expect(Merchant.find(existing_id).reference).to eq("merchant_old")
    expect(Merchant.find(existing_id).email).to eq("old@merchant.test")
    expect(Merchant.find_by(id: new_id)).to be_nil
    expect(csv_import.error_rows).to eq([
      already_processed_error(2),
      { "line" => 3, "column" => "reference", "message" => "Reference has already been taken" }
    ])
  end

  it "rolls back when a merchant id is processed after validation" do
    csv_import = create(:csv_import, kind: "merchants")
    store_csv(csv_import, <<~CSV)
      id;reference;email;live_on;disbursement_frequency;minimum_monthly_fee
      11111111-1111-4111-8111-111111111111;padberg_group;info@other.test;2023-02-01;DAILY;0.0
    CSV
    allow(ActiveRecord::Base).to receive(:transaction).and_wrap_original do |method, *args, **kwargs, &block|
      method.call(*args, **kwargs) do
        if kwargs[:requires_new]
          create(:merchant, id: "11111111-1111-4111-8111-111111111111", reference: "padberg_group")
        end
        block.call
      end
    end

    described_class.call(csv_import: csv_import)

    csv_import.reload
    expect(csv_import).to be_failed
    expect(Merchant.count).to eq(0)
    expect(csv_import.error_rows).to eq([ already_processed_error(2) ])
    expect(csv_import.errors_txt).to eq("#{already_processed_line(2)}\n")
  end

  it "rejects a reference taken after validation and writes nothing" do
    csv_import = create(:csv_import, kind: "merchants")
    store_csv(csv_import, <<~CSV)
      id;reference;email;live_on;disbursement_frequency;minimum_monthly_fee
      11111111-1111-4111-8111-111111111111;padberg_group;info@other.test;2023-02-01;DAILY;0.0
    CSV
    allow(ActiveRecord::Base).to receive(:transaction).and_wrap_original do |method, *args, **kwargs, &block|
      method.call(*args, **kwargs) do
        create(:merchant, reference: "padberg_group") if kwargs[:requires_new]
        block.call
      end
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
    allow(ActiveRecord::Base).to receive(:transaction).and_wrap_original do |method, *args, **kwargs, &block|
      method.call(*args, **kwargs) do
        merchant.update!(live_on: Date.new(2023, 3, 1)) if kwargs[:requires_new]
        block.call
      end
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

  it "keeps the last merchant row when the id is repeated" do
    csv_import = create(:csv_import, kind: "merchants")
    store_csv(csv_import, <<~CSV)
      id;reference;email;live_on;disbursement_frequency;minimum_monthly_fee
      86312006-4d7e-45c4-9c28-788f4aa68a62;first_group;first@merchant.test;2023-02-01;DAILY;0.0
      86312006-4d7e-45c4-9c28-788f4aa68a62;last_group;last@merchant.test;2023-02-01;WEEKLY;15.0
    CSV

    described_class.call(csv_import: csv_import)

    merchant = Merchant.find("86312006-4d7e-45c4-9c28-788f4aa68a62")
    expect(csv_import.reload).to be_succeeded
    expect(Merchant.count).to eq(1)
    expect(merchant.reference).to eq("last_group")
    expect(merchant.email).to eq("last@merchant.test")
    expect(csv_import.imported_count).to eq(1)
  end

  it "keeps the last merchant row when the same id is repeated across batches" do
    previous = ENV["CSV_IMPORT_BATCH_SIZE"]
    ENV["CSV_IMPORT_BATCH_SIZE"] = "1"
    csv_import = create(:csv_import, kind: "merchants")
    store_csv(csv_import, <<~CSV)
      id;reference;email;live_on;disbursement_frequency;minimum_monthly_fee
      86312006-4d7e-45c4-9c28-788f4aa68a62;first_group;first@merchant.test;2023-02-01;DAILY;0.0
      86312006-4d7e-45c4-9c28-788f4aa68a62;last_group;last@merchant.test;2023-02-01;WEEKLY;15.0
    CSV

    described_class.call(csv_import: csv_import)

    merchant = Merchant.find("86312006-4d7e-45c4-9c28-788f4aa68a62")
    expect(csv_import.reload).to be_succeeded
    expect(Merchant.count).to eq(1)
    expect(merchant.reference).to eq("last_group")
    expect(merchant.email).to eq("last@merchant.test")
  ensure
    previous ? ENV["CSV_IMPORT_BATCH_SIZE"] = previous : ENV.delete("CSV_IMPORT_BATCH_SIZE")
  end

  it "rolls back when postgres rejects a merchant reference" do
    csv_import = create(:csv_import, kind: "merchants")
    store_csv(csv_import, <<~CSV)
      id;reference;email;live_on;disbursement_frequency;minimum_monthly_fee
      86312006-4d7e-45c4-9c28-788f4aa68a62;padberg_group;info@padberg-group.com;2023-02-01;DAILY;0.0
    CSV
    allow(Merchant).to receive(:insert_all!).and_raise(ActiveRecord::RecordNotUnique.new("duplicate key"))

    described_class.call(csv_import: csv_import)

    csv_import.reload
    expect(csv_import).to be_failed
    expect(csv_import.error_message).to eq("duplicate key")
    expect(Merchant.count).to eq(0)
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

  it "keeps the last order when the same id is repeated across batches" do
    previous = ENV["CSV_IMPORT_BATCH_SIZE"]
    ENV["CSV_IMPORT_BATCH_SIZE"] = "1"
    create(:merchant, reference: "padberg_group", live_on: Date.new(2023, 2, 1))
    csv_import = create(:csv_import, kind: "orders")
    store_csv(csv_import, <<~CSV)
      id;merchant_reference;amount;created_at
      e653f3e14bc4;padberg_group;10.00;2023-02-01
      e653f3e14bc4;padberg_group;102.29;2023-02-01
    CSV

    described_class.call(csv_import: csv_import)

    order = Order.find_by!(external_id: "e653f3e14bc4")
    expect(csv_import.reload).to be_succeeded
    expect(Order.count).to eq(1)
    expect(order.amount_cents).to eq(10_229)
    expect(order.commission_cents).to eq(98)
  ensure
    previous ? ENV["CSV_IMPORT_BATCH_SIZE"] = previous : ENV.delete("CSV_IMPORT_BATCH_SIZE")
  end

  it "fails the import when processed orders sit among new rows and writes nothing else" do
    merchant = create(:merchant, reference: "padberg_group", live_on: Date.new(2023, 2, 1))
    disbursement = create(:disbursement, merchant: merchant)
    disbursed = create(
      :order,
      merchant: merchant,
      disbursement: disbursement,
      external_id: "e653f3e14bc4",
      ordered_on: Date.new(2023, 2, 1),
      amount_cents: 10_229,
      commission_cents: 98
    )
    waiting = create(
      :order,
      merchant: merchant,
      external_id: "aaaaaaaaaaaa",
      ordered_on: Date.new(2023, 2, 2),
      amount_cents: 5_000,
      commission_cents: 48
    )
    csv_import = create(:csv_import, kind: "orders")
    store_csv(csv_import, <<~CSV)
      id;merchant_reference;amount;created_at
      e653f3e14bc4;padberg_group;102.29;2023-02-01
      aaaaaaaaaaaa;padberg_group;50.00;2023-02-02
      bbbbbbbbbbbb;padberg_group;10.00;2023-02-03
    CSV
    phases = []
    allow(ActiveRecord::Base).to receive(:transaction).and_wrap_original do |method, *args, **kwargs, &block|
      phases << :write if kwargs[:requires_new]
      method.call(*args, **kwargs, &block)
    end

    expect {
      described_class.call(csv_import: csv_import)
    }.not_to have_enqueued_job

    expect(phases).to eq([])
    expect(csv_import.reload).to be_failed
    expect(csv_import.imported_count).to eq(0)
    expect(disbursed.reload.disbursement_id).to eq(disbursement.id)
    expect(disbursed.amount_cents).to eq(10_229)
    expect(waiting.reload.disbursement_id).to be_nil
    expect(waiting.amount_cents).to eq(5_000)
    expect(Order.find_by(external_id: "bbbbbbbbbbbb")).to be_nil
    expect(csv_import.error_rows).to eq([ already_processed_error(2), already_processed_error(3) ])
    expect(csv_import.errors_txt).to eq("#{already_processed_line(2)}\n#{already_processed_line(3)}\n")
  end

  it "fails a repeated orders file and leaves the stored orders unchanged" do
    create(:merchant, reference: "padberg_group", live_on: Date.new(2023, 2, 1))
    csv = <<~CSV
      id;merchant_reference;amount;created_at
      e653f3e14bc4;padberg_group;102.29;2023-02-01
      aaaaaaaaaaaa;padberg_group;50.00;2023-02-02
    CSV
    first = create(:csv_import, kind: "orders")
    store_csv(first, csv)
    described_class.call(csv_import: first)
    expect(first.reload).to be_succeeded
    expect(Order.count).to eq(2)

    second = create(:csv_import, kind: "orders")
    store_csv(second, csv)

    expect {
      described_class.call(csv_import: second)
    }.not_to have_enqueued_job

    expect(second.reload).to be_failed
    expect(Order.count).to eq(2)
    expect(Order.find_by!(external_id: "e653f3e14bc4").amount_cents).to eq(10_229)
    expect(Order.find_by!(external_id: "aaaaaaaaaaaa").amount_cents).to eq(5_000)
    expect(second.error_rows).to eq([ already_processed_error(2), already_processed_error(3) ])
    expect(second.errors_txt).to eq("#{already_processed_line(2)}\n#{already_processed_line(3)}\n")
  end

  it "rolls back the write when the order id is processed after validation" do
    create(:merchant, reference: "padberg_group", live_on: Date.new(2023, 2, 1))
    csv_import = create(:csv_import, kind: "orders")
    store_csv(csv_import, <<~CSV)
      id;merchant_reference;amount;created_at
      e653f3e14bc4;padberg_group;102.29;2023-02-01
    CSV
    allow(ActiveRecord::Base).to receive(:transaction).and_wrap_original do |method, *args, **kwargs, &block|
      method.call(*args, **kwargs) do
        if kwargs[:requires_new]
          merchant = Merchant.find_by!(reference: "padberg_group")
          create(
            :order,
            merchant: merchant,
            external_id: "e653f3e14bc4",
            ordered_on: Date.new(2023, 2, 1),
            amount_cents: 1_000,
            commission_cents: 10
          )
        end
        block.call
      end
    end

    described_class.call(csv_import: csv_import)

    expect(csv_import.reload).to be_failed
    expect(Order.count).to eq(0)
    expect(csv_import.error_rows).to eq([ already_processed_error(2) ])
    expect(csv_import.errors_txt).to eq("#{already_processed_line(2)}\n")
  end

  it "imports a zero amount and keeps the commission at zero cents" do
    create(:merchant, reference: "padberg_group", live_on: Date.new(2023, 2, 1))
    csv_import = create(:csv_import, kind: "orders")
    store_csv(csv_import, <<~CSV)
      id;merchant_reference;amount;created_at
      e653f3e14bc4;padberg_group;0.00;2023-02-01
    CSV

    described_class.call(csv_import: csv_import)

    order = Order.find_by!(external_id: "e653f3e14bc4")
    expect(csv_import.reload).to be_succeeded
    expect(order.amount_cents).to eq(0)
    expect(order.commission_cents).to eq(0)
  end

  it "reads merchants by column name when the header order changes" do
    csv_import = create(:csv_import, kind: "merchants")
    store_csv(csv_import, <<~CSV)
      email;minimum_monthly_fee;disbursement_frequency;live_on;reference;id
      info@padberg-group.com;15.0;WEEKLY;2023-02-01;padberg_group;86312006-4d7e-45c4-9c28-788f4aa68a62
    CSV

    described_class.call(csv_import: csv_import)

    merchant = Merchant.find("86312006-4d7e-45c4-9c28-788f4aa68a62")
    expect(csv_import.reload).to be_succeeded
    expect(merchant.reference).to eq("padberg_group")
    expect(merchant.email).to eq("info@padberg-group.com")
    expect(merchant).to be_weekly
    expect(merchant.live_on).to eq(Date.new(2023, 2, 1))
    expect(merchant.minimum_monthly_fee_cents).to eq(1_500)
  end

  it "rolls the file back when a required column, a date, a frequency, or an amount is invalid" do
    create(:merchant, reference: "padberg_group", live_on: Date.new(2023, 2, 1))
    cases = {
      "orders" => [
        [
          "id;merchant_reference;created_at\ne653f3e14bc4;padberg_group;2023-02-01\n",
          { "line" => 2, "column" => "amount", "message" => "is blank" }
        ],
        [
          "id;merchant_reference;amount;created_at\ne653f3e14bc4;padberg_group;10.00;2023-02-31\n",
          { "line" => 2, "column" => "created_at", "message" => "is invalid" }
        ],
        [
          "id;merchant_reference;amount;created_at\ne653f3e14bc4;padberg_group;abc;2023-02-01\n",
          { "line" => 2, "column" => "amount", "message" => "is invalid" }
        ]
      ],
      "merchants" => [
        [
          "id;reference;email;live_on;disbursement_frequency;minimum_monthly_fee\n86312006-4d7e-45c4-9c28-788f4aa68a62;padberg_group;info@padberg-group.com;2023-02-01;MONTHLY;0.0\n",
          { "line" => 2, "column" => "disbursement_frequency", "message" => "Disbursement frequency is not included in the list" }
        ]
      ]
    }

    cases.each do |kind, files|
      files.each do |content, error_row|
        csv_import = create(:csv_import, kind:)
        store_csv(csv_import, content)

        described_class.call(csv_import: csv_import)

        expect(csv_import.reload).to be_failed
        expect(csv_import.error_rows).to eq([ error_row ])
      end
    end

    expect(Order.count).to eq(0)
    expect(Merchant.count).to eq(1)
  end

  it "rejects an empty file and a header-only file and runs nothing" do
    contents = [
      "",
      "id;reference;email;live_on;disbursement_frequency;minimum_monthly_fee\n",
      "id;merchant_reference;amount;created_at\n"
    ]

    contents.each do |content|
      kind = content.include?("merchant_reference") ? "orders" : "merchants"
      csv_import = create(:csv_import, kind:)
      store_csv(csv_import, content)

      expect {
        described_class.call(csv_import: csv_import)
      }.not_to have_enqueued_job

      csv_import.reload
      expect(csv_import).to be_failed
      expect(csv_import.imported_count).to eq(0)
      expect(csv_import.error_message).to eq("CSV has no rows")
    end

    expect(Merchant.count).to eq(0)
    expect(Order.count).to eq(0)
  end

  it "rejects a CSV that is not the SeQura model and runs nothing" do
    contents = {
      "merchants" => <<~CSV,
        id;reference;email;live_on;disbursement_frequency;minimum_monthly_fee;notes
        86312006-4d7e-45c4-9c28-788f4aa68a62;padberg_group;info@padberg-group.com;2023-02-01;DAILY;0.0;extra
      CSV
      "orders" => <<~CSV
        id;merchant_reference;amount;created_at;notes
        e653f3e14bc4;padberg_group;10.00;2023-02-01;extra
      CSV
    }

    contents.each do |kind, content|
      csv_import = create(:csv_import, kind:)
      store_csv(csv_import, content)

      expect {
        described_class.call(csv_import: csv_import)
      }.not_to have_enqueued_job

      csv_import.reload
      expect(csv_import).to be_failed
      expect(csv_import.imported_count).to eq(0)
      expect(csv_import.error_message).to eq("CSV is not the model used by SeQura")
      expect(csv_import.error_rows).to eq([
        { "line" => 1, "column" => "notes", "message" => "CSV is not the model used by SeQura" }
      ])
    end

    expect(Merchant.count).to eq(0)
    expect(Order.count).to eq(0)
  end

  it "rejects a UTF-8 BOM and runs nothing" do
    csv_import = create(:csv_import, kind: "merchants")
    store_csv(csv_import, "\uFEFF" + <<~CSV)
      id;reference;email;live_on;disbursement_frequency;minimum_monthly_fee
      86312006-4d7e-45c4-9c28-788f4aa68a62;padberg_group;info@padberg-group.com;2023-02-01;DAILY;0.0
    CSV

    expect {
      described_class.call(csv_import: csv_import)
    }.not_to have_enqueued_job

    expect(csv_import.reload).to be_failed
    expect(csv_import.error_message).to eq("CSV contains characters outside the SeQura files")
    expect(Merchant.count).to eq(0)
  end

  it "rejects a file that is not UTF-8 and runs nothing" do
    csv_import = create(:csv_import, kind: "merchants")
    store_csv(csv_import, <<~CSV.encode("ISO-8859-1"))
      id;reference;email;live_on;disbursement_frequency;minimum_monthly_fee
      86312006-4d7e-45c4-9c28-788f4aa68a62;padberg_group;josé@padberg.test;2023-02-01;DAILY;0.0
    CSV

    expect {
      described_class.call(csv_import: csv_import)
    }.not_to have_enqueued_job

    expect(csv_import.reload).to be_failed
    expect(csv_import.error_message).to eq("CSV is not valid UTF-8")
    expect(Merchant.count).to eq(0)
  end

  it "rejects characters that do not appear in the SeQura files and runs nothing" do
    csv_import = create(:csv_import, kind: "merchants")
    store_csv(csv_import, <<~CSV)
      id;reference;email;live_on;disbursement_frequency;minimum_monthly_fee
      86312006-4d7e-45c4-9c28-788f4aa68a62;padberg_group;josé@padberg.test;2023-02-01;DAILY;0.0
    CSV

    expect {
      described_class.call(csv_import: csv_import)
    }.not_to have_enqueued_job

    expect(csv_import.reload).to be_failed
    expect(csv_import.error_message).to eq("CSV contains characters outside the SeQura files")
    expect(Merchant.count).to eq(0)
  end

  it "rounds an amount with a third decimal place up to the next cent" do
    create(:merchant, reference: "padberg_group", live_on: Date.new(2023, 2, 1))
    csv_import = create(:csv_import, kind: "orders")
    store_csv(csv_import, <<~CSV)
      id;merchant_reference;amount;created_at
      e653f3e14bc4;padberg_group;1.239;2023-02-01
    CSV

    described_class.call(csv_import: csv_import)

    order = Order.find_by!(external_id: "e653f3e14bc4")
    expect(csv_import.reload).to be_succeeded
    expect(order.amount_cents).to eq(124)
    expect(order.commission_cents).to eq(2)
  end

  describe "two imports at once" do
    self.use_transactional_tests = false

    after do
      Order.delete_all
      Merchant.delete_all
      CsvImport.delete_all
    end

    it "keeps the first committed order when another import writes the same id" do
      create(:merchant, reference: "padberg_group", live_on: Date.new(2023, 2, 1))
      first = create(:csv_import, kind: "orders")
      second = create(:csv_import, kind: "orders")
      store_csv(first, <<~CSV)
        id;merchant_reference;amount;created_at
        e653f3e14bc4;padberg_group;10.00;2023-02-01
      CSV
      store_csv(second, <<~CSV)
        id;merchant_reference;amount;created_at
        e653f3e14bc4;padberg_group;102.29;2023-02-02
      CSV

      import_together(first, second, ImportCsvService::OrdersService)

      winner, loser = winner_and_loser(first, second)
      order = Order.find_by!(external_id: "e653f3e14bc4")
      expect(Order.count).to eq(1)
      expect(loser.error_rows).to eq([ already_processed_error(2) ])
      expect(order.amount_cents).to eq(winner == first ? 1_000 : 10_229)
      expect(order.ordered_on).to eq(winner == first ? Date.new(2023, 2, 1) : Date.new(2023, 2, 2))
    end

    it "keeps the first committed merchant when another import writes the same id" do
      first = create(:csv_import, kind: "merchants")
      second = create(:csv_import, kind: "merchants")
      store_csv(first, <<~CSV)
        id;reference;email;live_on;disbursement_frequency;minimum_monthly_fee
        86312006-4d7e-45c4-9c28-788f4aa68a62;padberg_group;first@padberg.test;2023-02-01;DAILY;0.0
      CSV
      store_csv(second, <<~CSV)
        id;reference;email;live_on;disbursement_frequency;minimum_monthly_fee
        86312006-4d7e-45c4-9c28-788f4aa68a62;padberg_group;second@padberg.test;2023-02-01;DAILY;0.0
      CSV

      import_together(first, second, ImportCsvService::MerchantsService)

      winner, loser = winner_and_loser(first, second)
      merchant = Merchant.find("86312006-4d7e-45c4-9c28-788f4aa68a62")
      expect(Merchant.count).to eq(1)
      expect(loser.error_rows).to eq([ already_processed_error(2) ])
      expect(merchant.email).to eq(winner == first ? "first@padberg.test" : "second@padberg.test")
    end

    def import_together(first, second, service_class)
      arrived = Queue.new
      release = Queue.new
      allow_any_instance_of(service_class).to receive(:guard_concurrent_changes!).and_wrap_original do |method, *args, **kwargs, &block|
        arrived << true
        release.pop
        method.call(*args, **kwargs, &block)
      end

      threads = [ first, second ].map do |csv_import|
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            described_class.call(csv_import: csv_import)
          end
        end
      end

      Timeout.timeout(5) { 2.times { arrived.pop } }
    ensure
      2.times { release << true }
      threads&.each { |thread| thread.join(5) }
    end

    def winner_and_loser(first, second)
      imports = [ first, second ].map(&:reload)
      expect(imports.map(&:status)).to contain_exactly("succeeded", "failed")
      [ imports.find(&:succeeded?), imports.find(&:failed?) ]
    end
  end

  def already_processed_error(line)
    { "line" => line, "column" => "id", "message" => ImportCsvService::ALREADY_PROCESSED_MESSAGE }
  end

  def already_processed_line(line)
    "line #{line}, column id: #{ImportCsvService::ALREADY_PROCESSED_MESSAGE}"
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
