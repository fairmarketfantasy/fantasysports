class AddDayToGameRosters < ActiveRecord::Migration
  def change
    add_column :game_rosters, :day, :date
  end
end
