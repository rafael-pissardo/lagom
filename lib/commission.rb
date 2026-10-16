class Commission
  THRESHOLDS = [
    { exclusive_upper_bound_cents: 5_000, rate_numerator: 100, rate_denominator: 10_000 },
    { exclusive_upper_bound_cents: 30_000, rate_numerator: 95, rate_denominator: 10_000 },
    { exclusive_upper_bound_cents: Float::INFINITY, rate_numerator: 85, rate_denominator: 10_000 }
  ].freeze

  def self.cents_for(amount_cents)
    raise ArgumentError, "amount must be non-negative" if amount_cents.negative?

    tier = THRESHOLDS.find { |candidate| amount_cents < candidate[:exclusive_upper_bound_cents] }
    Finance::Amount.percentage_ceil(amount_cents, tier[:rate_numerator], tier[:rate_denominator])
  end
end
