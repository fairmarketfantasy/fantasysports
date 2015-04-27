class DenormalizeNumRostersContests < ActiveRecord::Migration
  def change
  	add_column :contests, :num_rosters, :integer, :default => 0
  	change_column :contests, :invitation_code, :string, :null => true
  	rename_column :contests, :owner, :owner_id
  	add_column :rosters, :cancelled, :boolean, :default=>false
  end
end
