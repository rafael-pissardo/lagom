class OrdersController < ApplicationController
  def index
    @merchant = Merchant.find(params[:merchant_id])
    @orders = @merchant.orders.order(ordered_on: :desc, created_at: :desc).limit(100)
  end
end
