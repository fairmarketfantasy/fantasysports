class AddPositionToRostersPlayers < ActiveRecord::Migration
  def change
    add_column :rosters_players, :position, :string
  end
end
