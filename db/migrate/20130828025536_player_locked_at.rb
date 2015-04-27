class PlayerLockedAt < ActiveRecord::Migration
  def change
    add_column :market_players, :locked_at, :timestamp, :null => true
    rename_column :market_players, :initial_price, :shadow_bets
    change_column :market_players, :bets, :decimal, :default => 0
  end
end
