require "rails_helper"

RSpec.describe Commission do
  describe ".cents_for" do
    it "charges 1.00% below 50 euros" do
      expect(described_class.cents_for(4_999)).to eq(50)
    end

    it "charges 0.95% from 50 euros inclusive to below 300 euros" do
      expect(described_class.cents_for(5_000)).to eq(48)
      expect(described_class.cents_for(29_999)).to eq(285)
    end

    it "charges 0.85% from 300 euros inclusive" do
      expect(described_class.cents_for(30_000)).to eq(255)
      expect(described_class.cents_for(37_333)).to eq(318)
    end

    it "rejects negative amounts" do
      expect { described_class.cents_for(-1) }.to raise_error(ArgumentError)
    end
  end
end
