class RemoveFinishedAndCanceledFromIndividualPredictions < ActiveRecord::Migration
  def change
    remove_column :individual_predictions, :finished, :boolean
    remove_column :individual_predictions, :cancelled, :boolean
  end
end
