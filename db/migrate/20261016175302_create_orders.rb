class CreateOrders < ActiveRecord::Migration[8.1]
  def change
    create_table :orders, id: :uuid do |t|
      t.string :external_id, null: false
      t.references :merchant, null: false, foreign_key: { on_delete: :restrict }, type: :uuid
      t.references :disbursement, null: true, foreign_key: { on_delete: :restrict }, type: :uuid
      t.date :ordered_on, null: false
      t.integer :amount_cents, null: false
      t.integer :commission_cents, null: false

      t.timestamps
    end

    add_index :orders, :external_id, unique: true
    add_index :orders, [ :merchant_id, :ordered_on ]
    add_index :orders,
      [ :merchant_id, :ordered_on ],
      where: "disbursement_id IS NULL",
      name: "index_orders_undisbursed_on_merchant_id_and_ordered_on"

    add_check_constraint :orders, "amount_cents >= 0", name: "orders_amount_cents_non_negative"
    add_check_constraint :orders, "commission_cents >= 0", name: "orders_commission_cents_non_negative"
  end
end
