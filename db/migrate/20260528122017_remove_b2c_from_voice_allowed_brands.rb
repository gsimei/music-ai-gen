class RemoveB2cFromVoiceAllowedBrands < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      UPDATE voices
      SET allowed_brands = array_remove(allowed_brands, 'b2c')
      WHERE 'b2c' = ANY(allowed_brands)
    SQL
  end

  def down
    # no-op: restoring b2c brand data is not needed
  end
end
