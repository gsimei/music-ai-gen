# frozen_string_literal: true

class CreateSoundtrackInputs < ActiveRecord::Migration[8.1]
  def change
    create_table :soundtrack_inputs do |t|
      t.references :order, null: false, foreign_key: true, index: false
      t.string  :input_type,          null: false
      t.string  :storage_key,         null: false
      t.string  :mureka_file_id
      t.string  :mureka_file_status
      t.integer :file_size_bytes
      t.string  :mime_type
      t.integer :duration_seconds
      t.datetime :scheduled_deletion_at
      t.datetime :deleted_at
      t.timestamps
    end

    add_index :soundtrack_inputs, :order_id, unique: true
  end
end
