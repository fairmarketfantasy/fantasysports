class AddPrivateToContests < ActiveRecord::Migration
  def change
    add_column :contests, :private, :boolean, :default => false
  end
end
