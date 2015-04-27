class RenameIndividualPredictionColumn < ActiveRecord::Migration
  def change
    rename_column :event_predictions, :less_or_more, :diff
  end
end
