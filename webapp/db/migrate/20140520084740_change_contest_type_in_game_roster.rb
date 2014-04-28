class ChangeContestTypeInGameRoster < ActiveRecord::Migration
  def change
    remove_column :game_rosters, :contest_type_id, :integer
    add_column :game_rosters, :contest_type_id, :integer
  end
end
