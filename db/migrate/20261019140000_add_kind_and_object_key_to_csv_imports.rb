class AddKindAndObjectKeyToCsvImports < ActiveRecord::Migration[8.1]
  def change
    add_column :csv_imports, :kind, :string
    add_column :csv_imports, :object_key, :string

    add_index :csv_imports, :object_key, unique: true, where: "object_key IS NOT NULL"
    add_check_constraint :csv_imports,
      "kind IS NULL OR kind IN ('merchants', 'orders')",
      name: "csv_imports_kind_check"
  end
end
