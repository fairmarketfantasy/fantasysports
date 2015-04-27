class AddRankIndexToRosters < ActiveRecord::Migration
  def change
    remove_index :rosters, :contest_id
    add_index :rosters, :owner_id
    add_index :rosters, :state
    add_index :rosters, [:contest_id, :contest_rank]
  end
end
