class AddMarketIdToIndividualPrediction < ActiveRecord::Migration
  def change
    add_column :individual_predictions, :market_id, :integer
  end
end
