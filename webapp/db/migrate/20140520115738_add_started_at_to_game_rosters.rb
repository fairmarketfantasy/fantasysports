class AddStartedAtToGameRosters < ActiveRecord::Migration
  def change
    add_column :game_rosters, :started_at, :datetime
  end
end
