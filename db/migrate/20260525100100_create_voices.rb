# frozen_string_literal: true

class CreateVoices < ActiveRecord::Migration[8.1]
  def change
    create_table :voices do |t|
      t.string :provider, null: false              # "mureka"
      t.string :external_id                        # ID da voz na Mureka (opcional — algumas vozes são descritas só via prompt)
      t.string :mureka_prompt                      # ex: "pop, female vocal, warm, emotional, italian" — vai no payload da Mureka
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description

      t.string :gender                             # "male" | "female" | "neutral"
      t.string :language_tags, array: true, default: []
      t.string :style_tags, array: true, default: []
      t.string :mood_tags, array: true, default: []

      t.string :sample_audio_url
      t.string :avatar_url

      t.integer :min_tier, default: 0              # 0 = standard, 1 = pro only
      t.string :allowed_brands, array: true, default: ["b2b", "b2c"]

      t.integer :display_order, default: 0
      t.boolean :active, default: true, null: false

      t.timestamps
    end

    # PG permite múltiplos NULLs em unique index — correto para external_id nullable
    add_index :voices, [:provider, :external_id], unique: true
    add_index :voices, :slug, unique: true
    add_index :voices, :active
    add_index :voices, :display_order
  end
end
