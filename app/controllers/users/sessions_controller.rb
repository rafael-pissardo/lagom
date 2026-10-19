class Users::SessionsController < Devise::SessionsController
  skip_before_action :authenticate_user!, only: %i[new create destroy]

  rate_limit to: 10, within: 3.minutes, only: :create, with: -> {
    redirect_to new_user_session_path, alert: I18n.t("sessions.create.alert")
  }

  def create
    request.params[:user] = sign_in_params.to_h
    super
  end

  protected

  def sign_in_params
    user = params[:user]
    if user.respond_to?(:permit)
      user.permit(:email, :password)
    elsif user.respond_to?(:slice)
      user.slice("email", "password")
    else
      {}
    end
  end
end
