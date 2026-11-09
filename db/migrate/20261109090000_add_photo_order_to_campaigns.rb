class AddPhotoOrderToCampaigns < ActiveRecord::Migration[8.1]
  def change
    add_column :campaigns, :photo_order, :jsonb, default: [], null: false
  end
end
