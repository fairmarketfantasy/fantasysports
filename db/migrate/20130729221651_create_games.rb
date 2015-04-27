class CreateGames < ActiveRecord::Migration
  def change
    create_table :venues do |t|
      t.string :stats_id
      t.string :country
      t.string :state
      t.string :city
      t.string :type
      t.string :name
      t.string :surface
    end
    add_index :venues, :stats_id

    create_table :games do |t|
      t.string :stats_id, :null => false
      t.integer :home_team_id, :null => false
      t.integer :away_team_id, :null => false
      t.string :status, :null => false
      t.date :game_day, :null => false
      t.timestamp :game_time, :null => false
      t.timestamps
    end
    add_index :games, :game_day
    add_index :games, :game_time
    add_index :games, :stats_id
    # This is here to make sure we handle game time changes correctly
    add_index :games, [:home_team_id, :away_team_id, :game_day], :unique => true
  end
end
