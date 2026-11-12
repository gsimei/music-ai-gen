class AddSelectedMusicToCampaigns < ActiveRecord::Migration[8.1]
  def change
    add_reference :campaigns, :selected_music_asset, foreign_key: { to_table: :order_assets }, null: true
  end
end
