module UuidHelper
  UUID_FORMAT = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i

  def uuid?(value)
    UUID_FORMAT.match?(value.to_s)
  end
end
