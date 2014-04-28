class AddDefaultValueToGameRosterIdInGamePrediction < ActiveRecord::Migration
  def change
    change_column :game_predictions, :game_roster_id, :integer, :null => false, :default => 0
  end
end
