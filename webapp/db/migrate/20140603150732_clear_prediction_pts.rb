class ClearPredictionPts < ActiveRecord::Migration
  def change
    PredictionPt.destroy_all
  end
end
