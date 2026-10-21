namespace :lagom do
  desc "Settle stored orders day by day through YEAR, as if the jobs had run on time. Example: YEAR=2023"
  task replay_year: :environment do
    year = ENV["YEAR"].to_s
    abort "YEAR must be a four-digit year" unless year.match?(/\A\d{4}\z/)

    puts "Replaying settlement through #{year}."
    ReplaySettlementService.call(year: year.to_i)
    puts "Done."
  end

  desc "Empty merchants, orders, disbursements, monthly fees and their adjustments, and CSV imports. Keeps users, Solid Queue, and migrations."
  task wipe_data: :environment do
    tables = %w[orders disbursements monthly_fee_adjustments monthly_fees merchants csv_imports]
    quoted = tables.map { |table| ActiveRecord::Base.connection.quote_table_name(table) }

    ActiveRecord::Base.connection.execute("TRUNCATE TABLE #{quoted.join(', ')}")

    puts "Wiped #{tables.join(', ')}. Kept users, Solid Queue, and schema_migrations."
  end
end
