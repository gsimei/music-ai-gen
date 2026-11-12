class AddCampaignCreativeHistoryAndCosts < ActiveRecord::Migration[8.1]
  def change
    add_reference :orders, :favorite_music_asset, foreign_key: { to_table: :order_assets, on_delete: :nullify }
    add_column :orders, :lyrics_revision_token, :string
    add_column :orders, :lyrics_revision_error, :text
    create_table :generation_costs do |t|
      t.references :order, null: false, foreign_key: true
      t.references :music_generation, foreign_key: { on_delete: :nullify }
      t.string :operation, null: false
      t.string :provider, null: false
      t.string :model
      t.string :status, null: false, default: "estimated"
      t.string :pricing_version, null: false
      t.decimal :estimated_usd, precision: 14, scale: 8
      t.decimal :usd_brl, precision: 10, scale: 4, null: false
      t.decimal :estimated_brl, precision: 14, scale: 8
      t.jsonb :usage, default: {}, null: false
      t.string :provider_request_id
      t.timestamps
    end
    add_index :generation_costs, [ :music_generation_id, :operation ], unique: true, where: "music_generation_id IS NOT NULL"
    reversible do |dir|
      dir.up do
        execute "UPDATE orders SET music_regen_limit = GREATEST(music_regen_limit, 2), lyrics_regen_limit = GREATEST(lyrics_regen_limit, 20) WHERE id IN (SELECT order_id FROM campaigns)"
      end
    end
  end
end
