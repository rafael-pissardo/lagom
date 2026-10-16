class ChargeMonthlyFee
  def self.call(merchant:, year:, month:)
    new(merchant:, year:, month:).call
  end

  def initialize(merchant:, year:, month:)
    @merchant = merchant
    @year = year
    @month = month
  end

  def call
    return if MonthlyFee.exists?(merchant: merchant, year: year, month: month)
    return if month_before_live_on?

    period_start = Date.new(year, month, 1)
    period_end = period_start.end_of_month

    commissions_cents = merchant.orders
      .where(ordered_on: period_start..period_end)
      .sum(:commission_cents)

    charged_cents = [ merchant.minimum_monthly_fee_cents - commissions_cents, 0 ].max

    MonthlyFee.create!(
      merchant: merchant,
      year: year,
      month: month,
      commissions_cents: commissions_cents,
      charged_cents: charged_cents
    )
  end

  private

  attr_reader :merchant, :year, :month

  def month_before_live_on?
    Date.new(year, month, 1) < merchant.live_on.beginning_of_month
  end
end
