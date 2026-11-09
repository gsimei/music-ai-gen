# frozen_string_literal: true

class AddStructureHintToBriefings < ActiveRecord::Migration[8.1]
  def change
    add_column :briefings, :structure_hint, :text
  end
end
