# frozen_string_literal: true

class CreateOrders < ActiveRecord::Migration[8.1]
  def change
    create_table :orders do |t|
      t.references :user, foreign_key: true, null: true

      t.string :reference, null: false             # "ORD-2026-A8F3K"
      t.string :brand, null: false                 # "b2b" | "b2c"
      t.string :locale, default: "it", null: false

      t.string :status, null: false, default: "pending"

      t.string :tier, null: false                  # "standard" | "pro" | "starter"
      t.integer :price_cents, null: false
      t.string :currency, default: "EUR", null: false

      t.integer :lyrics_regen_limit, null: false, default: 3
      t.integer :lyrics_regen_used, default: 0, null: false
      t.integer :music_regen_limit, null: false, default: 2
      t.integer :music_regen_used, default: 0, null: false

      t.string :stripe_session_id
      t.string :stripe_payment_intent_id
      t.string :stripe_charge_id
      t.datetime :paid_at

      # approved_lyrics_draft_id e approved_music_generation_id adicionados em
      # Migration 12 (20260525101100) para resolver FK circular com lyrics_drafts
      # e music_generations
      t.string :approved_variant                   # "a" | "b"
      t.datetime :approved_at

      t.string :delivery_email, null: false
      t.datetime :delivered_at
      t.datetime :first_download_at
      t.integer :download_count, default: 0

      t.text :internal_notes
      t.datetime :cancelled_at
      t.string :cancellation_reason

      t.timestamps
    end

    add_index :orders, :reference, unique: true
    add_index :orders, [:brand, :status]
    add_index :orders, :stripe_session_id
    add_index :orders, :stripe_payment_intent_id
    add_index :orders, :created_at
    add_index :orders, :paid_at
  end
end
