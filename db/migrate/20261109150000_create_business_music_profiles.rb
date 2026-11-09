class CreateBusinessMusicProfiles < ActiveRecord::Migration[8.1]
  def change
    create_table :business_music_profiles do |t|
      t.references :user, null: false, foreign_key: true
      t.string :business_name, null: false
      t.string :business_key, null: false
      t.string :musical_genre, null: false
      t.string :vocal_gender, null: false
      t.string :style, null: false
      t.string :music_notes, null: false, default: ""
      t.timestamps
    end
    add_index :business_music_profiles, [:user_id, :business_key], unique: true
  end
end
