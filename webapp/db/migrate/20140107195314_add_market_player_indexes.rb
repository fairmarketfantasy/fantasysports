class AddMarketPlayerIndexes < ActiveRecord::Migration
  def change
    add_index :market_players, [:market_id, :player_id], :unique => true
    remove_index :market_players, [:player_id, :market_id]
  end
end
