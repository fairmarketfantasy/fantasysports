class ChangeMarketPlayerScoreToDecimal < ActiveRecord::Migration
  def change
    change_column :market_players, :score, :decimal, :null => true, :default => 0
  end
end
