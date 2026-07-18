class AddNotesToClosedPositions < ActiveRecord::Migration[7.2]
  def change
    add_column :closed_positions, :notes, :text
  end
end
