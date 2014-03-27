class AddStateToIndividualPredictions < ActiveRecord::Migration
  def change
    add_column :individual_predictions, :state, :string
  end
end
