class CreateMonthlyFeeAdjustments < ActiveRecord::Migration[8.1]
  def change
    create_table :monthly_fee_adjustments, id: :uuid do |t|
      t.references :monthly_fee, null: false, foreign_key: { on_delete: :restrict }, type: :uuid
      t.integer :commissions_cents, null: false
      t.integer :credit_cents, null: false, default: 0

      t.timestamps
    end

    add_index :monthly_fee_adjustments, [ :monthly_fee_id, :commissions_cents ], unique: true, name: "index_monthly_fee_adjustments_on_fee_and_commissions"

    add_check_constraint :monthly_fee_adjustments, "commissions_cents >= 0", name: "monthly_fee_adjustments_commissions_cents_non_negative"
    add_check_constraint :monthly_fee_adjustments, "credit_cents >= 0", name: "monthly_fee_adjustments_credit_cents_non_negative"
  end
end
