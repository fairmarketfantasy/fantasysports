class AddActiveToSports < ActiveRecord::Migration
  def change
    add_column :sports, :is_active, :boolean, :default => true
  end
end
