class MakeMarketPlayersTestFriendly < ActiveRecord::Migration
  def change
    change_column :market_players, :initial_price, :decimal, :null => true
  end
end
