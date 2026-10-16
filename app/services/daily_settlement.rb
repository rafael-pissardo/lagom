class DailySettlement
  def self.call(as_of: Time.zone.today)
    new(as_of:).call
  end

  def initialize(as_of:)
    @as_of = as_of.to_date
  end

  def call
    Merchant.find_each do |merchant|
      DisburseMerchant.call(merchant: merchant, as_of: as_of)
    end

    previous_month = as_of.beginning_of_month.prev_month
    return unless as_of.day == 1

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
end
