class ReplaySettlementService
  TAIL_DAYS = 7

  def self.call(year:)
    new(year:).call
  end

  def initialize(year:)
    @year = Integer(year)
  end

  def call
    replay_days
    close_year
  end

  private

  attr_reader :year

  def replay_days
    first = Order.undisbursed.minimum(:ordered_on)
    return if first.nil? || first > last_day

    date = first
    while date <= last_day
      Rails.logger.info("Replaying settlement #{date}") if date.day == 1
      disburse(date)
      date = date.next_day
    end
  end

  def disburse(date)
    Merchant.find_each do |merchant|
      next if merchant.live_on > date

      DisburseMerchantService.call(merchant:, as_of: date, ordered_on_through: end_of_year)
      YearlyReportRefreshService.call(force: true)
    end
  end

  def close_year
    as_of = end_of_year.next_day
    Merchant.find_each do |merchant|
      month = merchant.live_on.beginning_of_month
      last = as_of.beginning_of_month.prev_month
      while month <= last
        ChargeMonthlyFeeService.call(merchant:, year: month.year, month: month.month)
        month = month.next_month
      end
      AdjustMonthlyFeesService.call(merchant:)
      YearlyReportRefreshService.call(force: true)
    end
  end

  def end_of_year
    Date.new(year, 12, 31)
  end

  def last_day
    end_of_year + TAIL_DAYS
  end
end
