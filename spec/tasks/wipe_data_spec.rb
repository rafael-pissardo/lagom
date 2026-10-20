require "rails_helper"
require "rake"

RSpec.describe "lagom:wipe_data" do
  before(:all) do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
  end

  it "empties the settlement tables and keeps users, Solid Queue, and migrations" do
    user = create(:user)
    merchant = create(:merchant)
    disbursement = create(:disbursement, merchant:)
    create(:order, merchant:, disbursement:)
    create(:monthly_fee, merchant:)
    create(:csv_import)
    SolidQueue::Job.insert({ queue_name: "default", class_name: "ImportCsvJob", created_at: Time.current, updated_at: Time.current })
    migrations_before = ActiveRecord::Base.connection.select_value("select count(*) from schema_migrations")

    expect { Rake::Task["lagom:wipe_data"].execute }.to output(/wiped/i).to_stdout

    expect(Merchant.count).to eq(0)
    expect(Order.count).to eq(0)
    expect(Disbursement.count).to eq(0)
    expect(MonthlyFee.count).to eq(0)
    expect(CsvImport.count).to eq(0)

    expect(User.find(user.id)).to be_present
    expect(SolidQueue::Job.count).to eq(1)
    expect(ActiveRecord::Base.connection.select_value("select count(*) from schema_migrations")).to eq(migrations_before)
  end
end
