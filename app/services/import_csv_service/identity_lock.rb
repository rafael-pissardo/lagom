module ImportCsvService::IdentityLock
  LOCK_SQL = "SELECT pg_advisory_xact_lock(hashtextextended(key, 0)) FROM unnest(ARRAY[?]::text[]) AS key".freeze

  private

  def lock_identities(namespace, ids)
    keys = ids.compact.uniq.sort.map { |id| "#{namespace}:#{id}" }
    return if keys.empty?

    ActiveRecord::Base.connection.execute(
      ActiveRecord::Base.sanitize_sql_array([ LOCK_SQL, keys ])
    )
  end
end
