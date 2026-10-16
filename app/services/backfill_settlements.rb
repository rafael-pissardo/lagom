class BackfillSettlements
  def self.call(as_of: nil)
    new(as_of).call
  end

  def initialize(as_of = nil)
    @as_of = as_of&.to_date || default_as_of
  end

  def call
    return if as_of.blank?

    disbursement_through = as_of + 7.days

    Merchant.find_each do |merchant|
      start_on = merchant.live_on
      start_on.upto(disbursement_through) do |day|
        DisburseMerchant.call(merchant: merchant, as_of: day)
      end

      month_cursor = merchant.live_on.beginning_of_month
      last_closed_month = as_of.beginning_of_month.prev_month

      while month_cursor <= last_closed_month
        ChargeMonthlyFee.call(
          merchant: merchant,
          year: month_cursor.year,
          month: month_cursor.month
        )
        month_cursor = month_cursor.next_month
      end
    end
  end

  private

  attr_reader :as_of

  def default_as_of
    Order.maximum(:ordered_on)
  end
end
