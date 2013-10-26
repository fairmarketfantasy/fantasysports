class AddGeneratedToRosters < ActiveRecord::Migration
  def change
    add_column :rosters, :is_generated, :boolean, :default => false
  end
end
