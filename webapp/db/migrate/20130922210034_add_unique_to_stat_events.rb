class AddUniqueToStatEvents < ActiveRecord::Migration
  def change
    add_index :stat_events, [:player_stats_id, :game_stats_id, :type], :unique => true
  end
end
