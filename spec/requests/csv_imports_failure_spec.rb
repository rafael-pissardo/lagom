require "rails_helper"

RSpec.describe "CsvImports failures", type: :request do
  it "shows an alert when the type or the file is missing" do
    user = create(:user)
    post user_session_path, params: { user: { email: user.email, password: "password123456" } }

    expect(Bucket).not_to receive(:put)

    post csv_imports_path, params: { csv_import: { kind: "", file: nil } }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Could not start the import")
    expect(response.body).to include("Choose Merchant or Orders.")
  end

  it "downloads a plain text file of line and column errors" do
    user = create(:user)
    post user_session_path, params: { user: { email: user.email, password: "password123456" } }
    csv_import = create(
      :csv_import,
      status: "failed",
      kind: "orders",
      object_key: "orders-20261019112103000.csv",
      error_rows: [ { "line" => 4, "column" => "amount", "message" => "is negative" } ]
    )

    get errors_csv_import_path(csv_import)

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/plain")
    expect(response.body).to eq("line 4, column amount: is negative\n")
    expect(response.headers["Content-Disposition"]).to include("orders-20261019112103000.csv.errors.txt")
  end
end
