# frozen_string_literal: true

class CreateBriefingMessagesAndRelaxBriefingConstraints < ActiveRecord::Migration[8.1]
  def change
    # briefing_messages — the conversational history that drives the chat UI
    create_table :briefing_messages do |t|
      t.references :order, null: false, foreign_key: true
      t.string     :role,    null: false   # "user" | "assistant"
      t.text       :content, null: false
      t.jsonb      :extracted_briefing, default: {}
      t.timestamps
    end

    add_index :briefing_messages, [ :order_id, :created_at ]

    # Allow the chat to create orders before briefing fields are filled
    change_column_null :briefings, :about,       true
    change_column_null :briefings, :music_style, true
  end
end
