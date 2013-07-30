class CreateGames < ActiveRecord::Migration
  def change
    create_table :games do |t|
      t.integer :home_team_id, :null => false
      t.integer :away_team_id, :null => false
      t.date :game_day, :null => false
      t.timestamp :game_time, :null => false
      t.timestamps
    end
    add_index :games, :game_time
    # This is here to make sure we handle game time changes correctly
    add_index :games, [:home_team_id, :away_team_id, :game_day], :unique => true
  end
end
