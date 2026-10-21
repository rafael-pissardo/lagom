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
    previous_month = as_of.beginning_of_month.prev_month

    merchants.find_each do |merchant|
      DisburseMerchantService.call(merchant: merchant, as_of: as_of)
      ChargeMonthlyFeeService.call(
        merchant: merchant,
        year: previous_month.year,
        month: previous_month.month
      )
      AdjustMonthlyFeesService.call(merchant: merchant)
    end
  end

  private

  attr_reader :frequency, :as_of

  def merchants
    Merchant.where(disbursement_frequency: frequency)
  end
end
