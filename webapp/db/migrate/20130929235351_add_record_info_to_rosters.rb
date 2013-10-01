class AddRecordInfoToRosters < ActiveRecord::Migration
  def change
    add_column :rosters, :wins, :integer
    add_column :rosters, :losses, :integer
  end
end
