class CsvImport < ApplicationRecord
  STATUSES = %w[pending processing succeeded failed].freeze

  has_one_attached :merchants_file
  has_one_attached :orders_file

  validates :status, presence: true, inclusion: { in: STATUSES }

  def pending?
    status == "pending"
  end

  def processing?
    status == "processing"
  end

  def succeeded?
    status == "succeeded"
  end

  def failed?
    status == "failed"
  end
end
