class DisbursementsController < ApplicationController
  def index
    disbursed_on = date_param(:disbursed_on)

    disbursements = Disbursement.includes(:merchant).order(disbursed_on: :desc)
    disbursements = disbursements.where(merchant: Merchant.search(params[:q])) if params[:q].present?
    disbursements = disbursements.where(disbursed_on:) if disbursed_on

    @pagy, @disbursements = pagy(:offset, disbursements)
  end

  def show
    @disbursement = Disbursement.includes(:merchant, :orders).find(params[:id])
  end
end
