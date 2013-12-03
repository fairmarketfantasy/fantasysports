class AddBonusesToUsers < ActiveRecord::Migration
  def change
    add_column :users, :bonuses, :text
  end
end
