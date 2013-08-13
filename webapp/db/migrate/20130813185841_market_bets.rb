class MarketBets < ActiveRecord::Migration
  def change
  	add_column :markets, :total_bets, :decimal
  	rename_column :rosters_players, :contest_roster_id, :roster_id
  	add_column :market_players, :bets, :decimal
  end
end
