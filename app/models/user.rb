class User < ApplicationRecord
  devise :database_authenticatable, :validatable

  normalizes :email, with: ->(email) { email.strip.downcase }
end
