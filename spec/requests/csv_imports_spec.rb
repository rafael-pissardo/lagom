require "rails_helper"

RSpec.describe "CsvImports", type: :request do
  it "enqueues processing and redirects with a notice" do
    user = create(:user)
    post session_path, params: { email_address: user.email_address, password: "password123456" }

    merchants = fixture_file_upload("merchants.csv", "text/csv")
    orders = fixture_file_upload("orders.csv", "text/csv")

    expect {
      post csv_imports_path, params: { csv_import: { merchants_file: merchants, orders_file: orders } }
    }.to have_enqueued_job(ImportCsvJob)

    expect(response).to redirect_to(csv_import_path(CsvImport.last))
    follow_redirect!
    expect(response.body).to include("processing")
  end
end
