class ChangeGamesMarkets < ActiveRecord::Migration
  def change
    change_column :games_markets, :game_stats_id, :string, :null => false
  end
end
