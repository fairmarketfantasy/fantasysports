class AddPositionToMarketPlayers < ActiveRecord::Migration
  def change
    add_column :market_players, :position, :string
  end
end
