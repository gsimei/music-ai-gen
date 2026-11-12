class AddCampaignVideoPersonalization < ActiveRecord::Migration[8.1]
  def change
    # A nil duration uses the entire recording; existing cuts stay at 30 seconds.
    add_column :order_assets, :excerpt_duration_seconds, :decimal, precision: 10, scale: 2, default: 30
    add_column :campaigns, :video_revision, :integer, null: false, default: 0
  end
end
