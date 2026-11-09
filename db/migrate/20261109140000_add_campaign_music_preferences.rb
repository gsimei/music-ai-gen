class AddCampaignMusicPreferences < ActiveRecord::Migration[8.1]
  def change
    add_column :campaigns, :musical_genre, :string, null: false, default: "auto"
    add_column :campaigns, :vocal_gender, :string, null: false, default: "auto"
    add_column :campaigns, :music_notes, :string, null: false, default: ""
  end
end
