class AddCampaignCtaAppearance < ActiveRecord::Migration[8.1]
  def change
    add_column :campaigns, :show_cta, :boolean, null: false, default: true
    add_column :campaigns, :cta_color, :string, limit: 7, null: false, default: "#d6f36b"
  end
end
