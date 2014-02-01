class AddExpectedPointsToMps < ActiveRecord::Migration
  def change
    add_column :market_players, :expected_points, :decimal, :default => 0
  end
end
