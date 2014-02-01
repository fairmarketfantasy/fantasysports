class AddRemoveBenchedToRosters < ActiveRecord::Migration
  def change
    add_column :rosters, :remove_benched, :boolean, :default => true
  end
end
