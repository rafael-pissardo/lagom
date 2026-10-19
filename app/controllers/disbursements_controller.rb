class DisbursementsController < ApplicationController
  def index
    @disbursements = Disbursement.includes(:merchant).order(disbursed_on: :desc).limit(100)
  end

  def show
    @disbursement = Disbursement.includes(:merchant, :orders).find(params[:id])
  end
end
