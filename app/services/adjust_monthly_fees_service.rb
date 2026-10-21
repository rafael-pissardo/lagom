class AdjustMonthlyFeesService
  def self.call(merchant:)
    new(merchant:).call
  end

  def initialize(merchant:)
    @merchant = merchant
  end

  def call
    Merchant.transaction(requires_new: true) do
      merchant.lock!
      totals = commissions_by_month
      charged_fees.each { |fee| adjust(fee, totals.fetch([ fee.year, fee.month ], 0)) }
    end
  end

  private

  attr_reader :merchant

  def charged_fees
    MonthlyFee.where(merchant_id: merchant.id).includes(:adjustments)
  end

  def commissions_by_month
    Order.where(merchant_id: merchant.id)
      .group(Arel.sql("EXTRACT(YEAR FROM ordered_on)::integer"), Arel.sql("EXTRACT(MONTH FROM ordered_on)::integer"))
      .sum(:commission_cents)
  end

  def adjust(fee, commissions_cents)
    return if commissions_cents == fee.known_commissions_cents

    due_cents = [ merchant.minimum_monthly_fee_cents - commissions_cents, 0 ].max
    gross_charged_cents = fee.charged_cents + fee.carried_credit_cents
    credit_cents = [ gross_charged_cents - fee.credited_cents - due_cents, 0 ].max
    fee.adjustments.create!(commissions_cents: commissions_cents, credit_cents: credit_cents)
  end
end
