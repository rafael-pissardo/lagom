class Rack::Attack
  throttle("logins/ip", limit: 10, period: 3.minutes) do |request|
    request.ip if request.path == "/users/sign_in" && request.post?
  end

  throttle("csv_imports/ip", limit: 5, period: 1.minute) do |request|
    request.ip if request.path == "/csv_imports" && request.post?
  end
end
