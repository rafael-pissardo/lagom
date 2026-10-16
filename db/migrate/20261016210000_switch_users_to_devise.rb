class SwitchUsersToDevise < ActiveRecord::Migration[8.1]
  def change
    rename_column :users, :email_address, :email
    rename_column :users, :password_digest, :encrypted_password
    drop_table :sessions
  end
end
