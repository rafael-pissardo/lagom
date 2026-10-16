class ApplicationController < ActionController::Base
  before_action :authenticate_user!

  allow_browser versions: :modern
  stale_when_importmap_changes

  private
    def after_sign_out_path_for(_resource_or_scope)
      new_user_session_path
    end
end
