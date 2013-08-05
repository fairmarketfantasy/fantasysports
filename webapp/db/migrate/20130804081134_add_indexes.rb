class AddIndexes < ActiveRecord::Migration
  def change
    add_index :teams, [:abbrev, :sport_id], :unique => true

    remove_index :games, :stats_id
    add_index :games, :stats_id, :unique => true

    remove_index :players, :stats_id
    add_index :players, :stats_id, :unique => true
    remove_column :players, :salary
    remove_column :players, :points_per_game

    remove_column :stat_events, :game_id
    remove_column :stat_events, :game_event_id
    remove_column :stat_events, :player_id
    add_column :stat_events, :player_stats_id, :string, :null => false
    add_column :stat_events, :game_stats_id, :string, :null => false
    add_column :stat_events, :game_event_stats_id, :string, :null => false
    add_index :stat_events, :game_stats_id
    add_index :stat_events, [:player_stats_id, :game_event_stats_id, :type], :unique => true, :name => "unique_stat_events"

    remove_column :game_events, :game_id
    add_column :game_events, :game_stats_id, :string, :null => false
    remove_index :game_events, :stats_id
    add_index :game_events, :stats_id, :unique => true
    add_index :game_events, :game_stats_id
  end
end
