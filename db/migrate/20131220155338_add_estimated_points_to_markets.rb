class AddEstimatedPointsToMarkets < ActiveRecord::Migration
  def change
    add_column :markets, :expected_total_points, :integer
    add_column :games_markets, :price_multiplier, :numeric, :default => 1
    add_column :market_players, :is_eliminated, :boolean, :default => false
  end
end
