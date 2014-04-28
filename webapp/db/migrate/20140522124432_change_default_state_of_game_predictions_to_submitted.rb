class ChangeDefaultStateOfGamePredictionsToSubmitted < ActiveRecord::Migration
  def change
    change_column :game_predictions, :state, :string,:null => false, :default => 'submitted'
  end
end
