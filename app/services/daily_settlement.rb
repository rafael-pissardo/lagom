class DailySettlement
  def self.call(as_of: Time.zone.today)
    new(as_of:).call
  end

  def initialize(as_of:)
    @as_of = as_of.to_date
  end

  def call
    Merchant.find_each { |merchant| settle_through(merchant) }

    previous_month = as_of.beginning_of_month.prev_month
    Merchant.find_each do |merchant|
      ChargeMonthlyFee.call(
        merchant: merchant,
        year: previous_month.year,
        month: previous_month.month
      )
    end
  end

  private

  attr_reader :as_of

  def settle_through(merchant)
    last_disbursed_on = merchant.disbursements.maximum(:disbursed_on)
    start_on = last_disbursed_on ? last_disbursed_on.next_day : merchant.live_on
    return if start_on > as_of

    start_on.upto(as_of) do |day|
      DisburseMerchant.call(merchant: merchant, as_of: day)
    end
  end
end
