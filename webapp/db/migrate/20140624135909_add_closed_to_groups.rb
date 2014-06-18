class AddClosedToGroups < ActiveRecord::Migration
  def change
    add_column :groups, :closed, :boolean
  end
end
