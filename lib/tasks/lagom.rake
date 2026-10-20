namespace :lagom do
  desc "Empty merchants, orders, disbursements, monthly fees, and CSV imports. Keeps users, Solid Queue, and migrations."
  task wipe_data: :environment do
    tables = %w[orders disbursements monthly_fees merchants csv_imports]
    quoted = tables.map { |table| ActiveRecord::Base.connection.quote_table_name(table) }

    ActiveRecord::Base.connection.execute("TRUNCATE TABLE #{quoted.join(', ')}")

    puts "Wiped #{tables.join(', ')}. Kept users, Solid Queue, and schema_migrations."
  end
end
