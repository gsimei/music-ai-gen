# frozen_string_literal: true

class CreateLyricsDrafts < ActiveRecord::Migration[8.1]
  def change
    create_table :lyrics_drafts do |t|
      t.references :order, foreign_key: true, null: false

      t.integer :version, null: false
      t.string :source, null: false                # "ai_generated" | "user_edited" | "regenerated"

      t.text :content, null: false
      t.jsonb :structure, default: {}

      t.text :user_feedback
      t.references :parent_draft, foreign_key: { to_table: :lyrics_drafts }, null: true

      t.string :llm_provider                       # "anthropic"
      t.string :llm_model                          # "claude-opus-4-7"
      t.string :prompt_version
      t.integer :input_tokens
      t.integer :output_tokens
      t.integer :latency_ms

      t.boolean :is_approved, default: false, null: false
      t.datetime :approved_at
      t.boolean :is_locked, default: false, null: false

      t.timestamps
    end

    add_index :lyrics_drafts, [:order_id, :version], unique: true
    add_index :lyrics_drafts, [:order_id, :is_approved]
  end
end
