class CsvImport < ApplicationRecord
  enum :kind, { merchants: "merchants", orders: "orders" }, validate: true
  enum :status, {
    pending: "pending",
    processing: "processing",
    succeeded: "succeeded",
    failed: "failed"
  }, validate: true, default: :pending

  attr_accessor :file

  validates :object_key, presence: true, uniqueness: true

  after_update_commit :broadcast_status, if: :saved_change_to_status?

  def self.object_key_for(kind, now: Time.current)
    raise ArgumentError, "unknown kind" unless kinds.key?(kind)

    "#{kind}-#{now.utc.strftime("%Y%m%d%H%M%S%L")}.csv"
  end

  def errors_txt
    return "" if error_rows.blank?

    lines = error_rows.map do |error_row|
      "line #{error_row["line"]}, column #{error_row["column"]}: #{error_row["message"]}"
    end
    "#{lines.join("\n")}\n"
  end

  private

  def broadcast_status
    broadcast_replace_to self,
      target: ActionView::RecordIdentifier.dom_id(self, :status),
      partial: "csv_imports/status",
      locals: { csv_import: self }
  end
end
