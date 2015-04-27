class AddPlayerPositions < ActiveRecord::Migration
  def change
    create_table :player_positions do |t|
      t.integer :player_id, :null => false
      t.string :position, :null => false

    end
    add_index :player_positions, [:player_id, :position], :unique => true
    add_index :player_positions, :position
  end
end
