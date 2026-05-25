# frozen_string_literal: true

class CreateRefundRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :refund_requests do |t|
      t.references :order, foreign_key: true, null: false
      t.references :user, foreign_key: true, null: false

      t.string :status, default: "pending"
      t.text :reason, null: false
      t.string :reason_category

      t.string :stripe_refund_id
      t.integer :refunded_amount_cents
      t.text :resolution_notes
      t.references :resolved_by, foreign_key: { to_table: :users }, null: true
      t.datetime :resolved_at

      t.timestamps
    end

    add_index :refund_requests, :status
  end
end
