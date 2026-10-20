class BackfillSettlementsJob < ApplicationJob
  queue_as :default

  def perform
    BackfillSettlements.call
  ensure
    YearlyReportRefresh.call(force: true)
  end
end
