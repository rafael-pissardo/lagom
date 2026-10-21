class ReportsController < ApplicationController
  def yearly
    @sort = YearlyReportSort.new(params)
    year = params[:year].to_s.strip
    rows = YearlyReportService.call
    adjustments = YearlyAdjustmentAuditService.call
    if year.present?
      rows = rows.select { |row| row.year.to_s.include?(year) }
      adjustments = adjustments.select { |row| row.charged_year.to_s.include?(year) || row.reference_year.to_s.include?(year) }
    end
    @pagy, @rows = pagy(:offset, @sort.apply(rows))
    @adjustments = adjustments
  end
end
