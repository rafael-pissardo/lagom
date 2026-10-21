class YearlyAdjustmentAuditService
  Row = Data.define(:charged_year, :reference_year, :adjustments_count, :credit_cents)

  def self.call
    new.call
  end

  def call
    MonthlyFeeAdjustment.joins(:monthly_fee).group(charged_year, "monthly_fees.year").pluck(
      charged_year,
      "monthly_fees.year",
      Arel.sql("COUNT(*)"),
      Arel.sql("SUM(monthly_fee_adjustments.credit_cents)")
    ).map { |charged, reference, count, credit|
      Row.new(charged_year: charged, reference_year: reference, adjustments_count: count, credit_cents: credit)
    }.sort_by { |row| [ row.charged_year, row.reference_year ] }
  end

  private

  def charged_year
    Arel.sql("EXTRACT(YEAR FROM monthly_fee_adjustments.created_at)::integer")
  end
end
