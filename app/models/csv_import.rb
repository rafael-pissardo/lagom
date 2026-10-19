class CsvImport < ApplicationRecord
  KINDS = %w[merchants orders].freeze
  STATUSES = %w[pending processing succeeded failed].freeze

  attr_accessor :file

  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :kind, presence: true, inclusion: { in: KINDS }
  validates :object_key, presence: true, uniqueness: true

  def self.object_key_for(kind, now: Time.current)
    raise ArgumentError, "unknown kind" unless KINDS.include?(kind)

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

  def merchants?
    kind == "merchants"
  end

  def orders?
    kind == "orders"
  end

  def errors_txt
    return "" if error_rows.blank?

    lines = error_rows.map do |error_row|
      "line #{error_row["line"]}, column #{error_row["column"]}: #{error_row["message"]}"
    end
    "#{lines.join("\n")}\n"
  end
end
