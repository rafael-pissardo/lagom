class CreateDisbursements < ActiveRecord::Migration[8.1]
  def change
    create_table :disbursements, id: :uuid do |t|
      t.references :merchant, null: false, foreign_key: { on_delete: :restrict }, type: :uuid
      t.date :disbursed_on, null: false
      t.string :reference, null: false
      t.integer :gross_cents, null: false
      t.integer :commission_cents, null: false
      t.integer :net_cents, null: false

      t.timestamps
    end

    add_index :disbursements, :reference, unique: true
    add_index :disbursements, [ :merchant_id, :disbursed_on ], unique: true
    add_index :disbursements, :disbursed_on

    add_check_constraint :disbursements, "gross_cents >= 0", name: "disbursements_gross_cents_non_negative"
    add_check_constraint :disbursements, "commission_cents >= 0", name: "disbursements_commission_cents_non_negative"
    add_check_constraint :disbursements, "net_cents >= 0", name: "disbursements_net_cents_non_negative"
  end
end
