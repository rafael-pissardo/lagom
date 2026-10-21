class ChargeMonthlyFeeService
  UNCOVERED_MONTH = <<~SQL.squish.freeze
    NOT EXISTS (
      SELECT 1 FROM monthly_fees
      WHERE monthly_fees.merchant_id = orders.merchant_id
        AND monthly_fees.year = EXTRACT(YEAR FROM orders.ordered_on)::integer
        AND monthly_fees.month = EXTRACT(MONTH FROM orders.ordered_on)::integer
    )
  SQL

  def self.call(merchant:, year:, month:)
    new(merchant:, year:, month:).call
  end

  def initialize(merchant:, year:, month:)
    @merchant = merchant
    @year = year
    @month = month
  end

  def call
    return if month_before_live_on?

    Merchant.transaction(requires_new: true) do
      merchant.lock!
      return if MonthlyFee.exists?(merchant: merchant, year: year, month: month)

      own_commissions_cents = commissions_cents(period_start..period_end)
      charge_cents = [ merchant.minimum_monthly_fee_cents - own_commissions_cents, 0 ].max
      carried_commissions_cents = [ unapplied_prior_commissions, 0 ].max

      fee = MonthlyFee.create!(
        merchant: merchant,
        year: year,
        month: month,
        commissions_cents: own_commissions_cents,
        charged_cents: charge_cents
      )
      if carried_commissions_cents.positive?
        fee.adjustments.create!(commissions_cents: carried_commissions_cents, credit_cents: 0, carried: true)
      end
    end
  end

  private

  attr_reader :merchant, :year, :month

  def month_before_live_on?
    period_start < merchant.live_on.beginning_of_month
  end

  def period_start
    @period_start ||= Date.new(year, month, 1)
  end

  def period_end
    period_start.end_of_month
  end

  def commissions_cents(range)
    Order.where(merchant_id: merchant.id, ordered_on: range).sum(:commission_cents)
  end

  def unapplied_prior_commissions
    prior_commissions - applied_commissions
  end

  def prior_commissions
    Order.where(merchant_id: merchant.id, ordered_on: merchant.live_on...period_start)
      .where(UNCOVERED_MONTH)
      .sum(:commission_cents)
  end

  def applied_commissions
    MonthlyFeeAdjustment.where(carried: true)
      .joins(:monthly_fee)
      .where(monthly_fees: { merchant_id: merchant.id })
      .sum(:commissions_cents)
  end
end
