class YearlyReportService
  Row = Data.define(
    :year,
    :disbursements_count,
    :amount_disbursed_cents,
    :order_fees_cents,
    :monthly_fees_count,
    :monthly_fees_amount_cents
  )

  def self.call
    new.call
  end

  def call
    years = (
      Disbursement.distinct.pluck(Arel.sql("EXTRACT(YEAR FROM disbursed_on)::integer")) +
      MonthlyFee.distinct.pluck(:year)
    ).uniq.sort

    years.map { |year| build_row(year) }
  end

  private

  def build_row(year)
    disbursements = Disbursement.where("EXTRACT(YEAR FROM disbursed_on) = ?", year)
    monthly_fees = MonthlyFee.where(year: year).charged

    Row.new(
      year: year,
      disbursements_count: disbursements.count,
      amount_disbursed_cents: disbursements.sum(:net_cents),
      order_fees_cents: disbursements.sum(:commission_cents),
      monthly_fees_count: monthly_fees.count,
      monthly_fees_amount_cents: monthly_fees.sum(:charged_cents)
    )
  end
end
