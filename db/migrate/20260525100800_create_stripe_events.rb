# frozen_string_literal: true

class CreateStripeEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :stripe_events do |t|
      t.string :stripe_event_id, null: false
      t.string :event_type, null: false
      t.string :status, default: "pending"

      t.references :order, foreign_key: true, null: true

      t.jsonb :payload, null: false
      t.text :error_message
      t.integer :attempt_count, default: 0

      t.datetime :processed_at
      t.timestamps
    end

    add_index :stripe_events, :stripe_event_id, unique: true
    add_index :stripe_events, :event_type
    add_index :stripe_events, :status
  end
end
