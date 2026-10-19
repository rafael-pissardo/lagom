class ImportCsv::MerchantCache
  def initialize(batch_size: ImportCsv.batch_size)
    @batch_size = batch_size
    @merchants = {}
    @reference_ids = {}
    @id_references = {}
  end

  def fetch(reference)
    return @merchants[reference] if @merchants.key?(reference)

    @merchants[reference] = Merchant.find_by(reference: reference)
  end

  def load_references(references)
    references.uniq.each_slice(@batch_size) do |slice|
      found = Merchant.where(reference: slice).pluck(:reference, :id).to_h
      slice.each { |reference| @reference_ids[reference] = found[reference] }
    end
  end

  def load_ids(ids)
    ids.uniq.each_slice(@batch_size) do |slice|
      found = Merchant.where(id: slice).pluck(:id, :reference).to_h
      slice.each { |id| @id_references[id] = found[id] }
    end
  end

  def lock_existing(ids:, references:)
    found_ids = []
    references.uniq.each_slice(@batch_size) do |slice|
      found_ids.concat(Merchant.where(reference: slice).pluck(:id))
    end
    ids.uniq.each_slice(@batch_size) do |slice|
      found_ids.concat(Merchant.where(id: slice).pluck(:id))
    end

    @merchants = {}
    found_ids.uniq.sort.each_slice(@batch_size) do |slice|
      Merchant.where(id: slice).order(:id).lock.each do |merchant|
        @merchants[merchant.reference] = merchant
      end
    end
    references.uniq.each { |reference| @merchants[reference] = nil unless @merchants.key?(reference) }
  end

  def reference_id(reference)
    @reference_ids[reference]
  end

  def reference_for_id(id)
    @id_references[id]
  end
end
