class AddCancelledToIndividualPredictions < ActiveRecord::Migration
  def change
    add_column :individual_predictions, :cancelled, :boolean
  end
end
