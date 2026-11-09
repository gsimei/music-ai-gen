# frozen_string_literal: true

class AddMurekaFieldsToMusicGenerationsAndOrderAssets < ActiveRecord::Migration[8.1]
  def change
    add_column :music_generations, :mureka_job_id, :string
    add_column :music_generations, :poll_count, :integer, default: 0, null: false
    add_column :music_generations, :model, :string

    add_column :order_assets, :variant_index, :integer
    add_column :order_assets, :provider_url, :string
    add_column :order_assets, :flac_url, :string
    add_column :order_assets, :wav_url, :string
    add_column :order_assets, :duration_ms, :integer

    add_index :music_generations, :mureka_job_id
  end
end
