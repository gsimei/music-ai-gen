# frozen_string_literal: true

class CreateEmailDeliveries < ActiveRecord::Migration[8.1]
  def change
    create_table :email_deliveries do |t|
      t.references :order, foreign_key: true, null: true
      t.references :user, foreign_key: true, null: true

      t.string :template, null: false
      t.string :recipient_email, null: false
      t.string :locale, null: false
      t.string :brand, null: false

      t.string :status, default: "queued"
      t.string :provider_message_id

      t.text :error_message
      t.datetime :sent_at
      t.datetime :opened_at
      t.datetime :clicked_at

      t.timestamps
    end

    add_index :email_deliveries, [:order_id, :template]
    add_index :email_deliveries, :status
  end
end
