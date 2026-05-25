# frozen_string_literal: true

class CreateGenerationJobs < ActiveRecord::Migration[8.1]
  def change
    create_table :generation_jobs do |t|
      t.references :order, foreign_key: true, null: false
      t.references :lyrics_draft, foreign_key: true, null: true

      t.string :provider, null: false              # "anthropic"
      t.string :model, null: false
      t.string :step, null: false                  # "lyrics_initial" | "lyrics_regen" | "lyrics_refine"
      t.string :status, default: "pending"

      t.string :prompt_version
      t.jsonb :request_payload, default: {}
      t.jsonb :response_payload, default: {}

      t.integer :input_tokens
      t.integer :output_tokens
      t.integer :total_tokens
      t.decimal :cost_usd, precision: 10, scale: 6

      t.text :error_message
      t.string :error_code
      t.integer :attempt_count, default: 0

      t.datetime :started_at
      t.datetime :finished_at
      t.integer :latency_ms

      t.timestamps
    end

    add_index :generation_jobs, [:order_id, :step]
    add_index :generation_jobs, :status
    add_index :generation_jobs, :created_at
  end
end
