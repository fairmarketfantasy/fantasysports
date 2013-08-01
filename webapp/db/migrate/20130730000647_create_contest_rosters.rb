class CreateContestRosters < ActiveRecord::Migration
  def change
    create_table :contest_rosters_players do |t|
      t.integer :player_id, :null => false
      t.integer :contest_roster_id, :null => false
    end
    add_index :contest_rosters_players, [:player_id, :contest_roster_id], :unique => true, :name => "contest_rosters_players_index"

    create_table :contest_rosters do |t|
      t.integer :owner_id, :null => false
      t.timestamps
    end
  end
end
