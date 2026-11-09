class AddCampaignAudioPreviewStatus < ActiveRecord::Migration[8.1]
  def change
    add_column :order_assets, :campaign_preview_status, :string, null: false, default: "pending"
  end
end
