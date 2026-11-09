# frozen_string_literal: true

class AddGenerationTypeToMusicGenerations < ActiveRecord::Migration[8.1]
  def change
    add_column :music_generations, :generation_type, :string, null: false, default: "song"
    add_index  :music_generations, :generation_type
  end
end
