require "rails_helper"

RSpec.describe YearlyReportRefresh do
  let(:merchant) { create(:merchant, reference: "refresh_co", live_on: Date.new(2022, 9, 1)) }

  before { described_class.reset! }

  it "tells the yearly report to refresh when a disbursement is saved" do
    expect {
      create(:disbursement, merchant:, disbursed_on: Date.new(2022, 9, 2), reference: "refresh_co20220902")
    }.to have_broadcasted_to("yearly_report").with { |html|
      expect(html).to include('action="refresh"')
    }
  end

  it "skips a second refresh inside the interval and still sends one when forced" do
    create(:disbursement, merchant:, disbursed_on: Date.new(2022, 9, 2), reference: "refresh_co20220902")

    expect {
      create(:disbursement, merchant:, disbursed_on: Date.new(2022, 9, 3), reference: "refresh_co20220903")
    }.not_to have_broadcasted_to("yearly_report")

    expect {
      described_class.call(force: true)
    }.to have_broadcasted_to("yearly_report")
  end

  it "tells the yearly report to refresh when a monthly fee is saved" do
    expect {
      create(:monthly_fee, merchant:, year: 2022, month: 9, charged_cents: 10)
    }.to have_broadcasted_to("yearly_report")
  end

  it "refreshes again when a settlement job finishes" do
    expect {
      DailySettlementJob.perform_now(Date.new(2022, 10, 2))
    }.to have_broadcasted_to("yearly_report")

    expect {
      BackfillSettlementsJob.perform_now
    }.to have_broadcasted_to("yearly_report")
  end
end
