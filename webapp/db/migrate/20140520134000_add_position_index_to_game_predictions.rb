class AddPositionIndexToGamePredictions < ActiveRecord::Migration
  def change
    add_column :game_predictions, :position_index, :integer
  end
end
