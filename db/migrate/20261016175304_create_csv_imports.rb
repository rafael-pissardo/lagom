class CreateCsvImports < ActiveRecord::Migration[8.1]
  def change
    create_table :csv_imports, id: :uuid do |t|
      t.string :status, null: false, default: "pending"
      t.string :merchants_filename
      t.string :orders_filename
      t.integer :merchants_imported_count, null: false, default: 0
      t.integer :orders_imported_count, null: false, default: 0
      t.integer :merchants_failed_count, null: false, default: 0
      t.integer :orders_failed_count, null: false, default: 0
      t.jsonb :error_rows, null: false, default: []
      t.text :error_message
      t.datetime :started_at
      t.datetime :finished_at

      t.timestamps
    end

    add_index :csv_imports, :status
    add_check_constraint :csv_imports,
      "status IN ('pending', 'processing', 'succeeded', 'failed')",
      name: "csv_imports_status_check"
  end
end
