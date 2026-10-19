class MerchantsController < ApplicationController
  SORTS = {
    "reference" => :reference,
    "email" => :email,
    "live_on" => :live_on,
    "frequency" => :disbursement_frequency,
    "fee" => :minimum_monthly_fee_cents
  }.freeze

  def index
    live_on = date_param(:live_on)

    merchants = Merchant.all
    merchants = merchants.search(params[:q]) if params[:q].present?
    merchants = merchants.where(live_on:) if live_on
    merchants = merchants.where(disbursement_frequency: params[:frequency]) if params[:frequency].present?

    @sort = IndexSort.new(params, columns: SORTS, fallback: { column: "reference", direction: "asc", order: { reference: :asc } })
    @pagy, @merchants = pagy(:offset, @sort.apply(merchants))
  end

  def show
    @merchant = Merchant.find(params[:id])
  end
end
