class ApplicationController < ActionController::Base
  include Pagy::Method

  before_action :authenticate_user!

  allow_browser versions: :modern
  stale_when_importmap_changes

  helper_method :filtering?

  private
    def after_sign_out_path_for(_resource_or_scope)
      new_user_session_path
    end

    def filtering?(*keys)
      keys.any? { |key| params[key].present? }
    end

    def date_param(key, format: "%Y-%m-%d")
      Date.strptime(params[key].to_s, format)
    rescue Date::Error
      nil
    end
end
