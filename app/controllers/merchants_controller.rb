class MerchantsController < ApplicationController
  def index
    @merchants = Merchant.order(:reference)
  end

  def show
    @merchant = Merchant.find(id_param)
  end

  private

  def id_param
    params.permit(:id)[:id]
  end
end
