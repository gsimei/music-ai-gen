# frozen_string_literal: true

class CreateMusicGenerations < ActiveRecord::Migration[8.1]
  def change
    create_table :music_generations do |t|
      t.references :order, foreign_key: true, null: false
      t.references :voice, foreign_key: true, null: false
      t.references :lyrics_draft, foreign_key: true, null: false

      t.integer :iteration, null: false            # 1 = inicial, 2 = primeira regen...

      t.string :provider, null: false              # "mureka"
      t.string :provider_task_id
      t.string :provider_model

      t.string :status, null: false, default: "pending"

      t.string :music_style, null: false
      t.string :mood
      t.string :tempo
      t.integer :target_duration_seconds

      t.text :user_feedback
      t.string :feedback_type
      t.references :parent_generation, foreign_key: { to_table: :music_generations }, null: true

      t.jsonb :request_payload, default: {}
      t.jsonb :response_payload, default: {}

      t.string :variant_a_provider_song_id
      t.string :variant_a_full_url
      t.string :variant_a_preview_url
      t.string :variant_a_stems_url
      t.integer :variant_a_duration_ms

      t.string :variant_b_provider_song_id
      t.string :variant_b_full_url
      t.string :variant_b_preview_url
      t.string :variant_b_stems_url
      t.integer :variant_b_duration_ms

      t.text :error_message
      t.string :error_code
      t.integer :attempt_count, default: 0

      t.datetime :submitted_at
      t.datetime :ready_at
      t.integer :total_latency_ms

      t.timestamps
    end

    add_index :music_generations, [:order_id, :iteration], unique: true
    add_index :music_generations, :provider_task_id
    add_index :music_generations, :status
  end
end
