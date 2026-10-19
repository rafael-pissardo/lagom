class SimplifyCsvImportCounts < ActiveRecord::Migration[8.1]
  def up
    add_column :csv_imports, :imported_count, :integer, null: false, default: 0
    add_column :csv_imports, :failed_count, :integer, null: false, default: 0

    execute <<~SQL.squish
      UPDATE csv_imports
      SET imported_count = merchants_imported_count + orders_imported_count,
          failed_count = merchants_failed_count + orders_failed_count
    SQL

    remove_column :csv_imports, :merchants_filename
    remove_column :csv_imports, :orders_filename
    remove_column :csv_imports, :merchants_imported_count
    remove_column :csv_imports, :orders_imported_count
    remove_column :csv_imports, :merchants_failed_count
    remove_column :csv_imports, :orders_failed_count
  end

  def down
    add_column :csv_imports, :merchants_filename, :string
    add_column :csv_imports, :orders_filename, :string
    add_column :csv_imports, :merchants_imported_count, :integer, null: false, default: 0
    add_column :csv_imports, :orders_imported_count, :integer, null: false, default: 0
    add_column :csv_imports, :merchants_failed_count, :integer, null: false, default: 0
    add_column :csv_imports, :orders_failed_count, :integer, null: false, default: 0

    execute <<~SQL.squish
      UPDATE csv_imports
      SET merchants_imported_count = CASE WHEN kind = 'merchants' THEN imported_count ELSE 0 END,
          orders_imported_count = CASE WHEN kind = 'orders' THEN imported_count ELSE 0 END,
          merchants_failed_count = CASE WHEN kind = 'merchants' THEN failed_count ELSE 0 END,
          orders_failed_count = CASE WHEN kind = 'orders' THEN failed_count ELSE 0 END
    SQL

    remove_column :csv_imports, :imported_count
    remove_column :csv_imports, :failed_count
  end
end
