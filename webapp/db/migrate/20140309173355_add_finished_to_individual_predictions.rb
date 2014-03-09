class AddFinishedToIndividualPredictions < ActiveRecord::Migration
  def change
    add_column :individual_predictions, :finished, :boolean
  end
end
