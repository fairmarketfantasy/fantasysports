class SwitchRostersPlayersIndex < ActiveRecord::Migration
  def change
    add_index :rosters_players, [:roster_id, :player_id], :unique => true
    remove_index :rosters_players, :name => 'contest_rosters_players_index'
  end
end
