class AddSwappedToRostersPlayer < ActiveRecord::Migration
  def change
    add_column :rosters_players, :swapped_player_name, :string
  end
end
