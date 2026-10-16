class BackfillSettlementsJob < ApplicationJob
  queue_as :default

  def perform
    BackfillSettlements.call
  end
end
