class RemovePlayerPredictions < ActiveRecord::Migration
  def change
    drop_table :player_predictions
  end
end
