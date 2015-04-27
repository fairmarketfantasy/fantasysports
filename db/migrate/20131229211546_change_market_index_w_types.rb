class ChangeMarketIndexWTypes < ActiveRecord::Migration
  def change
    remove_index :markets, [:closed_at, :started_at, :sport_id]
    add_index :markets, [:closed_at, :started_at, :game_type, :sport_id], :unique => true, :name => 'market_unique_idx'
  end
end
