class OrdersController < ApplicationController
  def index
    @merchant = Merchant.find(params[:merchant_id])
    ordered_on = date_param(:ordered_on)

    orders = @merchant.orders.order(ordered_on: :desc, created_at: :desc)
    orders = orders.search(params[:q]) if params[:q].present?
    orders = orders.where(ordered_on:) if ordered_on

    @pagy, @orders = pagy(:offset, orders)
  end
end
