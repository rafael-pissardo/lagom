require "rails_helper"

RSpec.describe Commission do
  describe ".cents_for" do
    it "rounds each order up to the next cent at the tier boundaries", :aggregate_failures do
      {
        0 => 0,                 # 0.00 €
        1 => 1,                 # 0.01 €
        4_999 => 50,            # 49.99 € at 1.00%
        5_000 => 48,            # 50.00 € at 0.95%
        5_001 => 48,            # 50.01 €, 47.5095 cents rounds up to 48
        6_174 => 59,            # 61.74 €, 58.653 cents rounds up to 59
        29_999 => 285,          # 299.99 €
        30_000 => 255,          # 300.00 € at 0.85%
        30_001 => 256,          # 300.01 €, 255.0085 cents rounds up to 256
        100_000_000 => 850_000  # 1,000,000.00 €, exact, still integer cents
      }.each do |amount_cents, commission_cents|
        expect(described_class.cents_for(amount_cents)).to eq(commission_cents)
      end
    end

    it "charges each order, so two commissions are not the commission of their sum" do
      expect(described_class.cents_for(4_000) + described_class.cents_for(4_000)).to eq(80)
      expect(described_class.cents_for(8_000)).to eq(76)
    end

    it "rejects negative amounts" do
      expect { described_class.cents_for(-1) }.to raise_error(ArgumentError)
    end
  end
end
