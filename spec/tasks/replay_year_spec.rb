require "rails_helper"
require "rake"

RSpec.describe "lagom:replay_year" do
  before(:all) do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
  end

  it "replays the given year" do
    allow(ReplaySettlementService).to receive(:call)

    with_env("YEAR" => "2023") do
      expect { Rake::Task["lagom:replay_year"].execute }.to output(/Replaying settlement through 2023/).to_stdout
    end

    expect(ReplaySettlementService).to have_received(:call).with(year: 2023)
  end

  it "rejects a YEAR that is not four digits" do
    allow(ReplaySettlementService).to receive(:call)

    with_env("YEAR" => "23") do
      expect { Rake::Task["lagom:replay_year"].execute }.to raise_error(SystemExit)
    end

    expect(ReplaySettlementService).not_to have_received(:call)
  end

  def with_env(values)
    previous = values.keys.to_h { |key| [ key, ENV[key] ] }
    values.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    yield
  ensure
    previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end
end
