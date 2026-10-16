class ReportsController < ApplicationController
  def yearly
    @rows = YearlyReport.call
  end
end
