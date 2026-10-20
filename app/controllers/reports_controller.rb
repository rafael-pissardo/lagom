class ReportsController < ApplicationController
  def yearly
    @sort = YearlyReportSort.new(params)
    rows = YearlyReportService.call
    year = params[:year].to_s.strip
    rows = rows.select { |row| row.year.to_s.include?(year) } if year.present?
    @pagy, @rows = pagy(:offset, @sort.apply(rows))
  end
end
