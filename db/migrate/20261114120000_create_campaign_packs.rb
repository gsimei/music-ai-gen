class CreateCampaignPacks < ActiveRecord::Migration[8.1]
  def change
    create_table :campaign_packs do |t|
      t.references :order, null: false, foreign_key: true, index: { unique: true }
      t.integer :quantity, null: false
      t.string :offer_code, null: false
      t.timestamps
    end
    add_check_constraint :campaign_packs, "quantity > 0", name: "campaign_packs_positive_quantity"
    add_reference :orders, :campaign_pack, foreign_key: true
    add_column :orders, :creation_token, :string
    add_index :orders, [ :user_id, :creation_token ], unique: true, where: "creation_token IS NOT NULL"
  end
end
