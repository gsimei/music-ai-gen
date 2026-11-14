class AddBrowserMediaUploadToCampaigns < ActiveRecord::Migration[8.1]
  def change
    add_column :campaigns, :media_upload_token, :string
    add_column :campaigns, :media_uploaded_at, :datetime
  end
end
