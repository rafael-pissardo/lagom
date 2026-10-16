class MerchantsController < ApplicationController
  def index
    @merchants = Merchant.order(:reference)
  end

  def show
    @merchant = Merchant.find(params[:id])
  end
end
