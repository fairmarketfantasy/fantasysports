class AddPtToPlayerPrediction < ActiveRecord::Migration
  def change
    add_column :player_predictions, :pt, :decimal, default: 0
  end
end
