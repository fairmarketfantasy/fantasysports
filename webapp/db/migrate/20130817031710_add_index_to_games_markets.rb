class AddIndexToGamesMarkets < ActiveRecord::Migration
  def change
    add_index :games_markets, [:market_id, :game_stats_id], :unique => true
  end
end
