if ENV["COVERAGE"]
  require "simplecov"

  SimpleCov.start "rails" do
    minimum_coverage 95
    add_filter "/spec/"
    add_filter "/config/"
    add_filter "/vendor/"
  end
end
