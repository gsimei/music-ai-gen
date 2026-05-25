# frozen_string_literal: true

class AddSecurityAndBusinessFieldsToUsers < ActiveRecord::Migration[8.1]
  def change
    # Devise :confirmable
    add_column :users, :confirmation_token, :string
    add_column :users, :confirmed_at, :datetime
    add_column :users, :confirmation_sent_at, :datetime
    add_column :users, :unconfirmed_email, :string

    # Devise :trackable
    add_column :users, :sign_in_count, :integer, default: 0, null: false
    add_column :users, :current_sign_in_at, :datetime
    add_column :users, :last_sign_in_at, :datetime
    add_column :users, :current_sign_in_ip, :string
    add_column :users, :last_sign_in_ip, :string

    # Devise :lockable
    add_column :users, :failed_attempts, :integer, default: 0, null: false
    add_column :users, :unlock_token, :string
    add_column :users, :locked_at, :datetime

    # Business fields
    add_column :users, :name, :string
    add_column :users, :locale, :string, default: "it", null: false
    add_column :users, :stripe_customer_id, :string
    add_column :users, :origin_brand, :string
    add_column :users, :role, :string, default: "customer"
    add_column :users, :guest, :boolean, default: false

    add_index :users, :confirmation_token, unique: true
    add_index :users, :unlock_token, unique: true
    add_index :users, :stripe_customer_id
    add_index :users, :origin_brand
  end
end
