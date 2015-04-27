class AddResultToIndividualPrediction < ActiveRecord::Migration
  def change
    add_column :individual_predictions, :game_result, :integer
  end
end
