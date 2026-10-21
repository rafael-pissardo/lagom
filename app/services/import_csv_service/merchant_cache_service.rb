class ImportCsvService::MerchantCacheService
  def initialize(batch_size: ImportCsvService.batch_size)
    @batch_size = batch_size
    reset!
  end

  def reset!
    @by_reference = {}
    @by_id = {}
  end

  def fetch(reference)
    load_references([ reference ])
    @by_reference[reference]
  end

  def by_id(id)
    load_ids([ id ])
    @by_id[id]
  end

  def load_references(references)
    missing = references.compact.uniq.reject { |reference| @by_reference.key?(reference) }
    missing.each_slice(@batch_size) do |slice|
      found = Merchant.where(reference: slice).index_by(&:reference)
      slice.each { |reference| @by_reference[reference] = found[reference] }
    end
  end

  def load_ids(ids)
    missing = ids.compact.uniq.reject { |id| @by_id.key?(id) }
    missing.each_slice(@batch_size) do |slice|
      found = Merchant.where(id: slice).index_by(&:id)
      slice.each { |id| @by_id[id] = found[id] }
    end
  end
end
