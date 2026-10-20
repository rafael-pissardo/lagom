class DailySettlementJob < ApplicationJob
  queue_as :default

  def perform(as_of = Time.zone.today)
    DailySettlementService.call(as_of: as_of)
  ensure
    YearlyReportRefreshService.call(force: true)
  end
end
