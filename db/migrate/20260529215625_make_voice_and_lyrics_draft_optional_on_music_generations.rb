class MakeVoiceAndLyricsDraftOptionalOnMusicGenerations < ActiveRecord::Migration[8.1]
  def change
    change_column_null :music_generations, :voice_id,        true
    change_column_null :music_generations, :lyrics_draft_id, true
  end
end
