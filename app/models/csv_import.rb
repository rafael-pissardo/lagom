class CsvImport < ApplicationRecord
  STATUSES = %w[pending processing succeeded failed].freeze

  enum :kind, { merchants: "merchants", orders: "orders" }, validate: true

  attr_accessor :file

  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :object_key, presence: true, uniqueness: true

  def self.object_key_for(kind, now: Time.current)
    raise ArgumentError, "unknown kind" unless kinds.key?(kind)

    "#{kind}-#{now.utc.strftime("%Y%m%d%H%M%S%L")}.csv"
  end

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

  def errors_txt
    return "" if error_rows.blank?

    lines = error_rows.map do |error_row|
      "line #{error_row["line"]}, column #{error_row["column"]}: #{error_row["message"]}"
    end
    "#{lines.join("\n")}\n"
  end
end
