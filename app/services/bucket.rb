require "aws-sdk-s3"

class Bucket
  class Error < StandardError; end

  LOCAL_DEFAULTS = {
    "AWS_ACCESS_KEY_ID" => "lagom",
    "AWS_SECRET_ACCESS_KEY" => "lagom-secret",
    "AWS_DEFAULT_REGION" => "us-east-1",
    "AWS_ENDPOINT_URL" => "http://localhost:9000",
    "AWS_S3_BUCKET_NAME" => "lagom"
  }.freeze

  def self.put(key:, body:)
    body.rewind if body.respond_to?(:rewind)
    client.put_object(bucket: bucket_name, key: key, body: body)
  rescue Aws::S3::Errors::ServiceError => error
    raise Error, error.message
  end

  def self.open(key)
    tempfile = Tempfile.new([ "csv-import", ".csv" ])
    client.get_object(bucket: bucket_name, key: key, response_target: tempfile)
    tempfile.rewind
    yield tempfile
  rescue Aws::S3::Errors::ServiceError => error
    raise Error, error.message
  ensure
    tempfile&.close!
  end

  def self.client
    Aws::S3::Client.new(
      access_key_id: env("AWS_ACCESS_KEY_ID"),
      secret_access_key: env("AWS_SECRET_ACCESS_KEY"),
      region: env("AWS_DEFAULT_REGION"),
      endpoint: env("AWS_ENDPOINT_URL"),
      force_path_style: true
    )
  end

  def self.bucket_name
    env("AWS_S3_BUCKET_NAME")
  end

  def self.env(key)
    value = ENV[key]
    return value if value.present?
    return LOCAL_DEFAULTS.fetch(key) if Rails.env.development?

    raise KeyError, "Missing #{key}"
  end

  private_class_method :client, :bucket_name, :env
end
