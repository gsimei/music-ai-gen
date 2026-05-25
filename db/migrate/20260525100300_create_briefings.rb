# frozen_string_literal: true

class CreateBriefings < ActiveRecord::Migration[8.1]
  def change
    create_table :briefings do |t|
      t.references :order, foreign_key: true, null: false, index: { unique: true }
      t.references :voice, foreign_key: true, null: true

      t.string :title
      t.text :about, null: false
      t.string :recipient
      t.string :occasion
      t.text :keywords
      t.text :avoid

      t.string :music_style, null: false
      t.string :mood
      t.string :tempo
      t.integer :target_duration_seconds, default: 120
      t.string :language, default: "it", null: false

      t.jsonb :extra_params, default: {}

      t.timestamps
    end

    add_index :briefings, :music_style
    add_index :briefings, :occasion
  end
end
