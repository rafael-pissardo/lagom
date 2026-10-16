require "spec_helper"

if ENV["COVERAGE"]
  require "simplecov"
  SimpleCov.start "rails" do
    minimum_coverage 95
    add_filter "/spec/"
    add_filter "/config/"
    add_filter "/vendor/"
    add_filter "/app/channels/"
    add_filter "/app/mailers/"
    add_filter "/app/views/pwa/"
    add_filter "/app/javascript/"
    add_filter "/lib/tasks/"
  end
end


ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
abort("The Rails environment is running in production mode!") if Rails.env.production?
require "rspec/rails"
require "view_component/test_helpers"
require "capybara/rspec"

Rails.root.glob("spec/support/**/*.rb").sort.each { |f| require f }

begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end

RSpec.configure do |config|
  config.fixture_paths = [ Rails.root.join("spec/fixtures") ]
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!
  config.include FactoryBot::Syntax::Methods
  config.include ViewComponent::TestHelpers, type: :component
  config.include Capybara::RSpecMatchers, type: :component
end


Shoulda::Matchers.configure do |config|
  config.integrate do |with|
    with.test_framework :rspec
    with.library :rails
  end
end
