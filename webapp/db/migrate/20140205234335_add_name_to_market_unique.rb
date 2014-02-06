class AddNameToMarketUnique < ActiveRecord::Migration
  def change
    add_index :markets, [:closed_at, :started_at, :name, :game_type, :sport_id], :name => 'markets_new_unique_idx', :unique => true
    remove_index :markets, :name => 'market_unique_idx'
  end
end
