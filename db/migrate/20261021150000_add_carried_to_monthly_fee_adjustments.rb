class AddCarriedToMonthlyFeeAdjustments < ActiveRecord::Migration[8.1]
  def change
    add_column :monthly_fee_adjustments, :carried, :boolean, null: false, default: false
    remove_index :monthly_fee_adjustments, name: "index_monthly_fee_adjustments_on_fee_and_commissions"
    add_index :monthly_fee_adjustments,
      [ :monthly_fee_id, :commissions_cents, :carried ],
      unique: true,
      name: "index_monthly_fee_adjustments_on_fee_and_commissions"
  end
end
