class UsePlayerStatsIdInMarketPlayers < ActiveRecord::Migration
  def change
  	add_column :market_players, :player_stats_id, :string, :null => true
  	add_column :rosters_players, :player_stats_id, :string, :null => true
  end
end
