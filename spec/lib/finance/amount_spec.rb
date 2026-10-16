require "rails_helper"

RSpec.describe Finance::Amount do
  describe ".from_decimal_string" do
    it "converts euro strings to cents" do
      expect(described_class.from_decimal_string("61.74")).to eq(6_174)
      expect(described_class.from_decimal_string("300")).to eq(30_000)
      expect(described_class.from_decimal_string("0.09")).to eq(9)
    end

    it "rejects blank and invalid values" do
      expect { described_class.from_decimal_string("") }.to raise_error(ArgumentError)
      expect { described_class.from_decimal_string("abc") }.to raise_error(ArgumentError)
    end
  end

  describe ".percentage_ceil" do
    it "rounds monetary percentages up to the next cent" do
      expect(described_class.percentage_ceil(6_174, 95, 10_000)).to eq(59)
      expect(described_class.percentage_ceil(4_999, 100, 10_000)).to eq(50)
      expect(described_class.percentage_ceil(5_000, 95, 10_000)).to eq(48)
      expect(described_class.percentage_ceil(30_000, 85, 10_000)).to eq(255)
    end
  end

  describe ".format_euros" do
    it "formats cents using the euro symbol" do
      expect(described_class.format_euros(6_174)).to eq("61.74 €")
      expect(described_class.format_euros(0)).to eq("0.00 €")
    end
  end
end
