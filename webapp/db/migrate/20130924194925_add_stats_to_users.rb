class AddStatsToUsers < ActiveRecord::Migration
  def change
    add_column :users, :total_points, :integer, :null => false, :default => 0
    add_column :users, :total_wins, :integer, :null => false, :default => 0
    add_column :users, :win_percentile, :decimal, :null => false, :default => 0
  end
end
