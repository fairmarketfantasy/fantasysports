class RemoveRosterFromIndividualPrediction < ActiveRecord::Migration
  def change
    remove_column :individual_predictions, :roster_id
  end
end
