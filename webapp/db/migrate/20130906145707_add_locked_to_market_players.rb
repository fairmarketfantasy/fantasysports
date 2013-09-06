class AddLockedToMarketPlayers < ActiveRecord::Migration
  def change
  	add_column :market_players, :locked, :boolean, :default => false
  	add_column :markets, :price_multiplier, :decimal, :default => 1
  end
end
