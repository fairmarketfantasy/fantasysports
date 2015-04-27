class AddScoreToMarketPlayers < ActiveRecord::Migration
  def change
    add_column :market_players, :score, :integer, :null => false, :default => 0
  end
end
