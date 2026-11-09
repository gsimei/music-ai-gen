# frozen_string_literal: true

class MakeOrderAssetsStorageKeyNullable < ActiveRecord::Migration[8.1]
  def change
    change_column_null :order_assets, :storage_key, true
  end
end
