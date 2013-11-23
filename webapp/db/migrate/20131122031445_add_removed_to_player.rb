class AddRemovedToPlayer < ActiveRecord::Migration
  def change
    add_column :players, :removed, :boolean, :default => false
  end
end
