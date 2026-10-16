require_relative "production"

Rails.application.configure do
  config.action_mailer.default_url_options = { host: ENV.fetch("APP_HOST", "lagom-staging.up.railway.app") }
end
