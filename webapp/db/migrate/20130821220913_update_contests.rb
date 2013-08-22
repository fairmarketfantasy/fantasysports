class UpdateContests < ActiveRecord::Migration
  def change
    remove_column :market_orders, :contest_id, :integer
    add_column :rosters, :submitted_at, :timestamp
    add_index :rosters, :submitted_at
  end
end
