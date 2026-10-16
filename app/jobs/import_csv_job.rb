class ImportCsvJob < ApplicationJob
  queue_as :default

  def perform(csv_import_id)
    csv_import = CsvImport.find(csv_import_id)
    ImportCsv.call(csv_import: csv_import)
  end
end
