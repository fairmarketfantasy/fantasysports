class UpdateRosters < ActiveRecord::Migration
  def change
    remove_column :rosters, :is_valid, :boolean
    remove_column :rosters, :cancelled
    add_column :rosters, :contest_type, :string, :null => false
    add_column :rosters, :state, :string, :null => false
    change_column :rosters, :contest_id, :integer, :null => true
  end
end
