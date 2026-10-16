class CreateMonthlyFees < ActiveRecord::Migration[8.1]
  def change
    create_table :monthly_fees, id: :uuid do |t|
      t.references :merchant, null: false, foreign_key: { on_delete: :restrict }, type: :uuid
      t.integer :year, null: false
      t.integer :month, null: false
      t.integer :commissions_cents, null: false, default: 0
      t.integer :charged_cents, null: false, default: 0

      t.timestamps
    end

    add_index :monthly_fees, [ :merchant_id, :year, :month ], unique: true
    add_index :monthly_fees, :year

    add_check_constraint :monthly_fees, "month >= 1 AND month <= 12", name: "monthly_fees_month_range"
    add_check_constraint :monthly_fees, "commissions_cents >= 0", name: "monthly_fees_commissions_cents_non_negative"
    add_check_constraint :monthly_fees, "charged_cents >= 0", name: "monthly_fees_charged_cents_non_negative"
  end
end
