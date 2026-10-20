require "rails_helper"

RSpec.describe BucketService do
  let(:env_keys) do
    %w[AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_DEFAULT_REGION AWS_ENDPOINT_URL AWS_S3_BUCKET_NAME]
  end

  around do |example|
    previous = env_keys.to_h { |key| [ key, ENV[key] ] }
    ENV["AWS_ACCESS_KEY_ID"] = "key"
    ENV["AWS_SECRET_ACCESS_KEY"] = "secret"
    ENV["AWS_DEFAULT_REGION"] = "us-east-1"
    ENV["AWS_ENDPOINT_URL"] = "http://localhost:9000"
    ENV["AWS_S3_BUCKET_NAME"] = "lagom"
    example.run
  ensure
    previous.each do |key, value|
      value.nil? ? ENV.delete(key) : ENV[key] = value
    end
  end

  it "stores an object using the bucket env vars" do
    client = instance_double(Aws::S3::Client)
    expect(Aws::S3::Client).to receive(:new).with(
      access_key_id: "key",
      secret_access_key: "secret",
      region: "us-east-1",
      endpoint: "http://localhost:9000",
      force_path_style: true
    ).and_return(client)
    expect(client).to receive(:put_object).with(bucket: "lagom", key: "orders-1.csv", body: kind_of(StringIO))

    described_class.put(key: "orders-1.csv", body: StringIO.new("id;amount\n"))
  end

  it "yields the object stored in the bucket" do
    client = instance_double(Aws::S3::Client)
    allow(Aws::S3::Client).to receive(:new).and_return(client)
    allow(client).to receive(:get_object) do |bucket:, key:, response_target:|
      expect(bucket).to eq("lagom")
      expect(key).to eq("orders-1.csv")
      response_target.write("csv-body")
    end

    body = nil
    described_class.open("orders-1.csv") { |file| body = file.read }
    expect(body).to eq("csv-body")
  end

  it "wraps storage failures" do
    client = instance_double(Aws::S3::Client)
    allow(Aws::S3::Client).to receive(:new).and_return(client)
    allow(client).to receive(:put_object).and_raise(Aws::S3::Errors::ServiceError.new(nil, "no such bucket"))

    expect {
      described_class.put(key: "a.csv", body: StringIO.new("x"))
    }.to raise_error(BucketService::Error, "no such bucket")
  end

  it "uses the local MinIO defaults in development when the env is unset" do
    env_keys.each { |key| ENV.delete(key) }
    allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("development"))
    client = instance_double(Aws::S3::Client, put_object: nil)
    expect(Aws::S3::Client).to receive(:new).with(
      hash_including(access_key_id: "lagom", secret_access_key: "lagom-secret", endpoint: "http://localhost:9000")
    ).and_return(client)

    described_class.put(key: "a.csv", body: StringIO.new("x"))
  end

  it "requires the env vars outside development" do
    env_keys.each { |key| ENV.delete(key) }
    allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))

    expect {
      described_class.put(key: "a.csv", body: StringIO.new("x"))
    }.to raise_error(KeyError, "Missing AWS_ACCESS_KEY_ID")
  end
end
