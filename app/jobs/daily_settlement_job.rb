class DailySettlementJob < ApplicationJob
  queue_as :default

  def perform(as_of = Time.zone.today)
    DailySettlement.call(as_of: as_of)
  ensure
    YearlyReportRefresh.call(force: true)
  end
end
