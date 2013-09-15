class DenormalizeMarketIdIntoRostersPlayers < ActiveRecord::Migration
  def change
  	add_column :rosters_players, :market_id, :integer, :null => true
  	add_index :rosters_players, :market_id
  	RostersPlayer.find_by_sql("update rosters_players set market_id = rosters.market_id from rosters where rosters_players.roster_id = rosters.id")
  	change_column :rosters_players, :market_id, :integer, :null => false
  end
end
