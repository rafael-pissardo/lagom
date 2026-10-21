class YearlyReportSort
  COLUMNS = {
    "year" => :year,
    "disbursements" => :disbursements_count,
    "amount_disbursed" => :amount_disbursed_cents,
    "order_fees" => :order_fees_cents,
    "monthly_fees_count" => :monthly_fees_count,
    "monthly_fees_charged" => :monthly_fees_charged_cents,
    "monthly_fee_adjustments" => :monthly_fee_adjustments_cents,
    "monthly_fees_amount" => :monthly_fees_amount_cents
  }.freeze

  attr_reader :column, :direction

  def initialize(params)
    requested = params[:sort].to_s

    if COLUMNS.key?(requested)
      @column = requested
      @direction = params[:direction].to_s.casecmp("desc").zero? ? "desc" : "asc"
    else
      @column = "year"
      @direction = "asc"
    end
  end

  def apply(rows)
    attribute = COLUMNS.fetch(column)

    rows.sort do |left, right|
      result = left.public_send(attribute) <=> right.public_send(attribute)
      result = -result if direction == "desc"
      result.zero? ? (left.year <=> right.year) : result
    end
  end
end
