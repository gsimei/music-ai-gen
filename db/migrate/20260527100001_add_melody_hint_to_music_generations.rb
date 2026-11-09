# frozen_string_literal: true

class AddMelodyHintToMusicGenerations < ActiveRecord::Migration[8.1]
  def change
    add_column :music_generations, :melody_hint, :text
  end
end
