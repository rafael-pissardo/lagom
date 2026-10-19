class OrdersController < ApplicationController
  def index
    @merchant = Merchant.find(merchant_id_param)
    @orders = @merchant.orders.order(ordered_on: :desc, created_at: :desc).limit(100)
  end

  private

  def merchant_id_param
    params.permit(:merchant_id)[:merchant_id]
  end
end
