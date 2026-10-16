email = ENV["OPERATOR_EMAIL"]
password = ENV["OPERATOR_PASSWORD"]

if Rails.env.local?
  email ||= "operator@lagom.local"
  password ||= "lagom-operator-password"
elsif email.blank? || password.blank?
  raise "OPERATOR_EMAIL and OPERATOR_PASSWORD are required in #{Rails.env}"
end

User.find_or_create_by!(email_address: email) do |user|
  user.password = password
end

puts "Operator ready: #{email}"
