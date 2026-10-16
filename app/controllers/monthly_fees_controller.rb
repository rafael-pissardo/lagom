class MonthlyFeesController < ApplicationController
  def index
    @monthly_fees = MonthlyFee.includes(:merchant).order(year: :desc, month: :desc).limit(200)
  end
end
