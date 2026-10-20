require "rails_helper"

RSpec.describe BackfillSettlementsJob do
  it "delegates to BackfillSettlementsService" do
    expect(BackfillSettlementsService).to receive(:call)

    described_class.perform_now
  end
end
