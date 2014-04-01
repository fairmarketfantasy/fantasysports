class AddPpgToPlayers < ActiveRecord::Migration
  def change
    add_column :players, :ppg, :decimal, default: 0
  end
end
