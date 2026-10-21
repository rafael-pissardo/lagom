module ImportCsvService::IdentityLock
  private

  def lock_identities(namespace, ids)
    keys = ids.compact.uniq.sort.map { |id| "#{namespace}:#{id}" }
    return if keys.empty?

    connection = ActiveRecord::Base.connection
    quoted = keys.map { |key| connection.quote(key) }.join(", ")
    connection.execute(<<~SQL.squish)
      SELECT pg_advisory_xact_lock(hashtextextended(key, 0))
      FROM unnest(ARRAY[#{quoted}]::text[]) AS key
    SQL
  end
end
