class AddBonuses < ActiveRecord::Migration
  def change
    add_column :rosters, :bonus_points, :integer, :default => 0
    add_column :rosters, :bonuses, :text
  end
end
