require "rails_helper"

RSpec.describe "CsvImports", type: :request do
  it "shows one import type and one file field" do
    user = create(:user)
    post user_session_path, params: { user: { email: user.email, password: "password123456" } }

    get new_csv_import_path

    expect(response.body).to include("Merchant")
    expect(response.body).to include("Orders")
    expect(response.body).to include('name="csv_import[file]"')
    expect(response.body).not_to include("merchants_file")

    form = Nokogiri::HTML(response.body).at_css("form[action='#{csv_imports_path}']")
    submit = form.at_css("button[type=submit]")
    expect(submit.text).to include("Start import")
    expect(submit["disabled"]).to eq("disabled")
    expect(submit.at_css("[data-csv-import-form-target=spinner]")["class"]).to include("hidden")
    expect(form["enctype"]).to eq("multipart/form-data")
    expect(form["data-action"]).to include("submit->csv-import-form#start")
  end

  it "stores the csv in the bucket, marks it processing, and enqueues the job" do
    user = create(:user)
    post user_session_path, params: { user: { email: user.email, password: "password123456" } }
    stored = {}
    allow(Bucket).to receive(:put) { |key:, body:| stored[key] = body.read }

    travel_to Time.utc(2026, 10, 19, 11, 21, 3) do
      expect {
        post csv_imports_path, params: {
          csv_import: {
            kind: "merchants",
            file: fixture_file_upload("merchants.csv", "text/csv")
          }
        }
      }.to have_enqueued_job(ImportCsvJob)
    end

    csv_import = CsvImport.last
    expect(stored.keys).to eq([ "merchants-20261019112103000.csv" ])
    expect(stored.fetch("merchants-20261019112103000.csv")).to include("padberg_group")
    expect(csv_import.object_key).to eq("merchants-20261019112103000.csv")
    expect(csv_import).to be_processing
    expect(response).to redirect_to(csv_import_path(csv_import))
    follow_redirect!
    expect(response.body).to include("processing")
  end

  it "does not create an import when the bucket rejects the file" do
    user = create(:user)
    post user_session_path, params: { user: { email: user.email, password: "password123456" } }
    allow(Bucket).to receive(:put).and_raise(Bucket::Error, "unavailable")

    expect {
      post csv_imports_path, params: {
        csv_import: {
          kind: "orders",
          file: fixture_file_upload("orders.csv", "text/csv")
        }
      }
    }.not_to change(CsvImport, :count)

    expect(ImportCsvJob).not_to have_been_enqueued
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Could not start the import")
  end

  it "refreshes import status only while a show is still processing" do
    user = create(:user)
    post user_session_path, params: { user: { email: user.email, password: "password123456" } }
    processing = create(:csv_import, status: "processing")
    finished = create(:csv_import, status: "succeeded")

    get csv_import_path(processing)
    expect(response.body).to include('data-controller="import-status"')
    expect(response.body).not_to include('http-equiv="refresh"')

    [ csv_import_path(finished), csv_imports_path, new_csv_import_path ].each do |path|
      get path
      expect(response.body).not_to include("import-status")
      expect(response.body).not_to include('http-equiv="refresh"')
    end
  end
end
