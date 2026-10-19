class DisbursementsController < ApplicationController
  SORTS = {
    "reference" => :reference,
    "disbursed_on" => :disbursed_on,
    "gross" => :gross_cents,
    "commission" => :commission_cents,
    "net" => :net_cents
  }.freeze

  def index
    disbursed_on = date_param(:disbursed_on)

    disbursements = Disbursement.includes(:merchant)
    disbursements = disbursements.where(merchant: Merchant.search(params[:q])) if params[:q].present?
    disbursements = disbursements.where(disbursed_on:) if disbursed_on

    @sort = IndexSort.new(params, columns: SORTS, fallback: { column: "disbursed_on", direction: "desc", order: { disbursed_on: :desc } })
    @pagy, @disbursements = pagy(:offset, @sort.apply(disbursements))
  end

  def show
    @disbursement = Disbursement.includes(:merchant, :orders).find(params[:id])
  end
end
