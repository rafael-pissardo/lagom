class MerchantsController < ApplicationController
  def index
    live_on = date_param(:live_on)

    merchants = Merchant.order(:reference)
    merchants = merchants.search(params[:q]) if params[:q].present?
    merchants = merchants.where(live_on:) if live_on
    merchants = merchants.where(disbursement_frequency: params[:frequency]) if params[:frequency].present?

    @pagy, @merchants = pagy(:offset, merchants)
  end

  def show
    @merchant = Merchant.find(params[:id])
  end
end
