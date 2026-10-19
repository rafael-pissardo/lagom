class ImportCsv::MerchantCache
  def initialize
    @merchants = {}
  end

  def fetch(reference)
    return @merchants[reference] if @merchants.key?(reference)

    @merchants[reference] = Merchant.find_by(reference: reference)
  end
end
