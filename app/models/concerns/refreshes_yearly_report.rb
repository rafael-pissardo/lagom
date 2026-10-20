module RefreshesYearlyReport
  extend ActiveSupport::Concern

  included do
    after_commit :refresh_yearly_report
  end

  private

  def refresh_yearly_report
    YearlyReportRefreshService.call
  end
end
