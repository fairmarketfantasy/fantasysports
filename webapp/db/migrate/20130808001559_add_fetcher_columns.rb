class AddFetcherColumns < ActiveRecord::Migration
  def change
    remove_index :game_events, :stats_id
    add_index :game_events, [:game_stats_id, :sequence_number], :unique => true
    remove_column :games, :home_team_id
    remove_column :games, :away_team_id
    add_column :games, :home_team, :string, :null => false
    add_column :games, :away_team, :string, :null => false
    add_column :games, :season_type, :string
    add_column :games, :season_week, :integer
    add_column :games, :season_year, :integer
    add_column :games, :network, :string
    add_column :game_events, :acting_team, :string
  end
end
