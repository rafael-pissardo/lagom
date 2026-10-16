class Users::SessionsController < Devise::SessionsController
  skip_before_action :authenticate_user!, only: %i[new create destroy]

  rate_limit to: 10, within: 3.minutes, only: :create, with: -> {
    redirect_to new_user_session_path, alert: I18n.t("sessions.create.alert")
  }
end
