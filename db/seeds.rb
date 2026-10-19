email = ENV["OPERATOR_EMAIL"].presence || "operator@lagom.local"
password = ENV["OPERATOR_PASSWORD"].presence || "lagom-operator-password"

User.find_or_create_by!(email: email) do |user|
  user.password = password
end

puts "Operator ready: #{email}"
