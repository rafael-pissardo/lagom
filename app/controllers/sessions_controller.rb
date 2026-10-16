class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[ new create ]
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_session_path, alert: t("sessions.create.alert") }

  def new
  end

  def create
    if user = User.authenticate_by(params.permit(:email_address, :password))
      start_new_session_for user
      redirect_to after_authentication_url, notice: t("sessions.create.notice")
    else
      redirect_to new_session_path, alert: t("sessions.create.alert")
    end
  end

  def destroy
    terminate_session
    redirect_to new_session_path, status: :see_other, notice: t("sessions.destroy.notice")
  end
end
