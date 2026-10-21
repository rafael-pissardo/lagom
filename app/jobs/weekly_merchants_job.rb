class WeeklyMerchantsJob < ApplicationJob
  queue_as :default

  def perform(as_of = Time.zone.today)
    SettleMerchantsService.call(frequency: "WEEKLY", as_of: as_of)
  ensure
    YearlyReportRefreshService.call(force: true)
  end
end
