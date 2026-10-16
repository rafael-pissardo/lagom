class CreateMerchants < ActiveRecord::Migration[8.1]
  def change
    create_table :merchants, id: :uuid do |t|
      t.string :reference, null: false
      t.string :email, null: false
      t.date :live_on, null: false
      t.string :disbursement_frequency, null: false
      t.integer :minimum_monthly_fee_cents, null: false, default: 0

      t.timestamps
    end

    add_index :merchants, :reference, unique: true
    add_index :merchants, :disbursement_frequency

    add_check_constraint :merchants,
      "disbursement_frequency IN ('DAILY', 'WEEKLY')",
      name: "merchants_disbursement_frequency_check"
    add_check_constraint :merchants,
      "minimum_monthly_fee_cents >= 0",
      name: "merchants_minimum_monthly_fee_cents_non_negative"
  end
end
