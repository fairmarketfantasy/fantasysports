class CreateStatEvents < ActiveRecord::Migration
  def change
    create_table :stat_events do |t|
      t.integer :player_id, :null => false
      t.integer :game_id, :null => false
      t.decimal :point_value, :null => false
      t.string :event_description, :null => false
      t.timestamps
    end
  end
end
