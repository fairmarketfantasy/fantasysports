class ConvertTotalPointsToFloat < ActiveRecord::Migration
  def change
    change_column :players, :total_points, :decimal, :null => true, :default => 0
  end
end
