class AddGamePredictionToGameRoster < ActiveRecord::Migration
  def change
    add_column :game_predictions, :game_roster_id, :integer
  end
end
