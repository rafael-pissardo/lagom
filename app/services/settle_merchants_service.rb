class SettleMerchantsService
  FREQUENCIES = Merchant.disbursement_frequencies.values.freeze

  def self.call(frequency:, as_of: Time.zone.today)
    new(frequency:, as_of:).call
  end

  def initialize(frequency:, as_of:)
    raise ArgumentError, "unknown frequency" unless FREQUENCIES.include?(frequency)

    @frequency = frequency
    @as_of = as_of.to_date
  end

  def call
    merchants.find_each do |merchant|
      DisburseMerchantService.call(merchant: merchant, as_of: as_of)
      charge_elapsed_months(merchant)
      AdjustMonthlyFeesService.call(merchant: merchant)
    end
  end

  private

  attr_reader :frequency, :as_of

  def merchants
    Merchant.where(disbursement_frequency: frequency)
  end

  def charge_elapsed_months(merchant)
    month = merchant.live_on.beginning_of_month
    last = as_of.beginning_of_month.prev_month
    while month <= last
      ChargeMonthlyFeeService.call(merchant: merchant, year: month.year, month: month.month)
      month = month.next_month
    end
  end
end
