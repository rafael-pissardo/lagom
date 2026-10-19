class MonthlyFeesController < ApplicationController
  SORTS = {
    "merchant" => ->(direction) { { merchant: { reference: direction } } },
    "year" => :year,
    "month" => :month,
    "commissions" => :commissions_cents,
    "charged" => :charged_cents
  }.freeze

  def index
    month = date_param(:month, format: "%Y-%m")

    monthly_fees = MonthlyFee.includes(:merchant)
    monthly_fees = monthly_fees.where(merchant: Merchant.search(params[:q])) if params[:q].present?
    monthly_fees = monthly_fees.in_month(month) if month
    monthly_fees = monthly_fees.charged if params[:charged] == "charged"
    monthly_fees = monthly_fees.zero if params[:charged] == "zero"

    @sort = IndexSort.new(params, columns: SORTS, fallback: { column: "year", direction: "desc", order: { year: :desc, month: :desc } })
    @pagy, @monthly_fees = pagy(:offset, @sort.apply(monthly_fees))
  end
end
