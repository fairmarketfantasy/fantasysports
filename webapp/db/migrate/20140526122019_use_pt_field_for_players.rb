class UsePtFieldForPlayers < ActiveRecord::Migration
  def change
    add_column :players, :pt, :decimal
    remove_column :players, :money_line
    remove_column :players, :rotation
  end
end
