class Rack::Attack
  throttle("csv_imports/ip", limit: 5, period: 1.minute) do |request|
    request.ip if request.path == "/csv_imports" && request.post?
  end
end
