class OrdersController < ApplicationController
  SORTS = {
    "external_id" => :external_id,
    "ordered_on" => :ordered_on,
    "amount" => :amount_cents,
    "commission" => :commission_cents
  }.freeze

  def index
    @merchant = Merchant.find(params[:merchant_id])
    ordered_on = date_param(:ordered_on)

    orders = @merchant.orders
    orders = orders.search(params[:q]) if params[:q].present?
    orders = orders.where(ordered_on:) if ordered_on

    @sort = IndexSort.new(
      params,
      columns: SORTS,
      fallback: { column: "ordered_on", direction: "desc", order: { ordered_on: :desc, created_at: :desc } }
    )
    @pagy, @orders = pagy(:offset, @sort.apply(orders))
  end
end
