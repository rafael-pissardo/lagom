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
    years.map { |year| build_row(year) }
  end

  private

  def years
    (disbursement_totals.keys + MonthlyFee.distinct.pluck(:year)).uniq.sort
  end

  def build_row(year)
    disbursements = disbursement_totals[year] || { count: 0, net: 0, commission: 0 }
    charged = charged_totals[year] || { count: 0, charged: 0 }

    Row.new(
      year: year,
      disbursements_count: disbursements[:count],
      amount_disbursed_cents: disbursements[:net],
      order_fees_cents: disbursements[:commission],
      monthly_fees_count: charged[:count],
      monthly_fees_amount_cents: charged[:charged]
    )
  end

  def disbursement_totals
    @disbursement_totals ||= Disbursement.group(year_of(:disbursed_on)).pluck(
      year_of(:disbursed_on),
      Arel.sql("COUNT(*)"),
      Arel.sql("SUM(net_cents)"),
      Arel.sql("SUM(commission_cents)")
    ).to_h { |year, count, net, commission| [ year, { count: count, net: net, commission: commission } ] }
  end

  def charged_totals
    @charged_totals ||= MonthlyFee.charged.group(:year).pluck(
      :year,
      Arel.sql("COUNT(*)"),
      Arel.sql("SUM(charged_cents)")
    ).to_h { |year, count, charged| [ year, { count: count, charged: charged } ] }
  end

  def year_of(column)
    Arel.sql("EXTRACT(YEAR FROM #{column})::integer")
  end
end
