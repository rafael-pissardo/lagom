class BackfillSettlementsJob < ApplicationJob
  queue_as :default

  def perform
    BackfillSettlementsService.call
  ensure
    YearlyReportRefreshService.call(force: true)
  end
end
