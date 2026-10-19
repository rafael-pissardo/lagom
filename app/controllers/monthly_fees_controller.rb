class MonthlyFeesController < ApplicationController
  def index
    month = date_param(:month, format: "%Y-%m")

    monthly_fees = MonthlyFee.includes(:merchant).order(year: :desc, month: :desc)
    monthly_fees = monthly_fees.where(merchant: Merchant.search(params[:q])) if params[:q].present?
    monthly_fees = monthly_fees.in_month(month) if month
    monthly_fees = monthly_fees.charged if params[:charged] == "charged"
    monthly_fees = monthly_fees.zero if params[:charged] == "zero"

    @pagy, @monthly_fees = pagy(:offset, monthly_fees)
  end
end
