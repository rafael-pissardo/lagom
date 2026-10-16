require "rails_helper"

RSpec.describe "CsvImports failures", type: :request do
  it "shows an alert when files are missing" do
    user = create(:user)
    post session_path, params: { email_address: user.email_address, password: "password123456" }

    post csv_imports_path, params: { csv_import: { merchants_file: nil, orders_file: nil } }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Could not start the import")
  end
end
