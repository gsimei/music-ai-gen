# frozen_string_literal: true

class CreateOrderAssets < ActiveRecord::Migration[8.1]
  def change
    create_table :order_assets do |t|
      t.references :order, foreign_key: true, null: false
      t.references :music_generation, foreign_key: true, null: true

      t.string :kind, null: false                  # "final_mp3" | "final_wav" | "stems_zip" | "lyrics_pdf"
      t.string :storage_key, null: false
      t.string :url
      t.datetime :url_expires_at

      t.integer :file_size_bytes
      t.string :mime_type
      t.string :checksum_sha256

      t.integer :download_count, default: 0
      t.datetime :last_downloaded_at

      t.timestamps
    end

    # NÃO único: um order pode ter mp3 + wav + stems + pdf (múltiplos por kind)
    add_index :order_assets, [:order_id, :kind]
  end
end
