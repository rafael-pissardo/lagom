# frozen_string_literal: true

Devise.setup do |config|
  config.mailer_sender = "noreply@lagom.local"
  require "devise/orm/active_record"

  config.case_insensitive_keys = [ :email ]
  config.strip_whitespace_keys = [ :email ]
  config.skip_session_storage = [ :http_auth ]
  config.stretches = Rails.env.test? ? 1 : 12
  config.sign_out_via = :delete
  config.responder.error_status = :unprocessable_content
  config.responder.redirect_status = :see_other
  config.navigational_formats = [ "*/*", :html, :turbo_stream ]
end
