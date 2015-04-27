class AddSportIdToMarket < ActiveRecord::Migration
  def change
    add_column :markets, :sport_id, :integer, :null => false
    change_column :markets, :shadow_bet_rate, :decimal, :null => false
  end
end
