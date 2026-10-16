class ApplicationComponent < ViewComponent::Base
  include Rails.application.routes.url_helpers

  delegate :t, :l, to: :helpers
end
