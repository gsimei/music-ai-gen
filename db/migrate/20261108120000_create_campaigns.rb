class CreateCampaigns < ActiveRecord::Migration[8.1]
  def change
    create_table :campaigns do |t|
      t.references :order, null: false, foreign_key: true, index: { unique: true }
      t.string :business_name, null: false
      t.string :offer, null: false
      t.string :contact, null: false
      t.string :style, null: false, default: "animado"
      t.string :call_to_action, null: false, default: "Peça pelo WhatsApp"
      t.string :video_status, null: false, default: "pending"
      t.text :video_error
      t.timestamps
    end
  end
end
