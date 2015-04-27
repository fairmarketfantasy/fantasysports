class AddCheckedToGames < ActiveRecord::Migration
  def change
    add_column :games, :checked, :boolean
  end
end
