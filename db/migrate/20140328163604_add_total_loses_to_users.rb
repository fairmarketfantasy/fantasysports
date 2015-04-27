class AddTotalLosesToUsers < ActiveRecord::Migration
  def change
    add_column :users, :total_loses, :integer, default: 0
  end
end
