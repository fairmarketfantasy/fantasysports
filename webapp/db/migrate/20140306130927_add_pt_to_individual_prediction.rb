class AddPtToIndividualPrediction < ActiveRecord::Migration
  def change
    add_column :individual_predictions, :pt, :decimal, :default => 0, :null => false
    add_column :individual_predictions, :award, :decimal, :default => 0, :null => false
    remove_column :event_predictions, :value, :integer
    add_column :event_predictions, :value, :decimal
  end
end
