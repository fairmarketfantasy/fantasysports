class AddUniqueIndexToMarkets < ActiveRecord::Migration
  def change
    add_index :markets, [:closed_at, :started_at, :sport_id], :unique => true
  end
end
