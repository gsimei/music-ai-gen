class AddCampaignRecoveryAndExcerptControls < ActiveRecord::Migration[8.1]
  def change
    add_column :music_generations, :submission_attempts, :integer, null: false, default: 0
    add_column :music_generations, :next_poll_at, :datetime
    add_column :music_generations, :poll_lease_until, :datetime
    add_index :music_generations, [ :status, :next_poll_at ]
    add_column :order_assets, :excerpt_start_seconds, :decimal, precision: 10, scale: 2
    add_column :order_assets, :preview_revision, :integer, null: false, default: 0
  end
end
