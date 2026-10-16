Rails.application.configure do
  config.mission_control.jobs.base_controller_class = "ApplicationController"
  config.mission_control.jobs.http_basic_auth_enabled = false
end
