module ImportCsvService::IdentityLock
  private

  def lock_identities(namespace, ids)
    ids.compact.uniq.sort.each do |id|
      ActiveRecord::Base.with_advisory_lock!(
        "#{namespace}:#{id}",
        transaction: true,
        blocking: true
      ) { :locked }
    end
  end
end
