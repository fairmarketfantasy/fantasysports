class ChangePredictionPts < ActiveRecord::Migration
  def change
    remove_column :prediction_pts, :is_group
    add_column :prediction_pts, :competition_type, :string
  end
end
