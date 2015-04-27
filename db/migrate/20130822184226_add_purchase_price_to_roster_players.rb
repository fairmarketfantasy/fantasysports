class AddPurchasePriceToRosterPlayers < ActiveRecord::Migration
  def change
    add_column :rosters_players, :purchase_price, :decimal, :null => false, :default => 1000
    change_column :rosters_players, :purchase_price, :decimal, :null => false, :default => nil
  end
end

