class ChangeTypeToActivity < ActiveRecord::Migration
  def change
    remove_index :stat_events, [:player_stats_id, :game_stats_id, :type]
    rename_column 'stat_events', 'type', 'activity'
    add_index :stat_events, [:player_stats_id, :game_stats_id, :activity], :unique => true, :name => 'player_game_activity'
  end
end
