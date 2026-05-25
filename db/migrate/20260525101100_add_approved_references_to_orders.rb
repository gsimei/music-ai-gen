# frozen_string_literal: true

class AddApprovedReferencesToOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :orders, :approved_lyrics_draft_id, :bigint
    add_column :orders, :approved_music_generation_id, :bigint
    add_foreign_key :orders, :lyrics_drafts, column: :approved_lyrics_draft_id
    add_foreign_key :orders, :music_generations, column: :approved_music_generation_id
    add_index :orders, :approved_lyrics_draft_id
    add_index :orders, :approved_music_generation_id
  end
end
