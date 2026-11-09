class AddLyricsSyncToOrderAssets < ActiveRecord::Migration[8.1]
  def change
    add_column :order_assets, :lyrics_sync, :jsonb, default: {}
  end
end
