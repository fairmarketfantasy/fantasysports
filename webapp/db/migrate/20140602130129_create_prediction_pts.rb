class CreatePredictionPts < ActiveRecord::Migration
  def change
    create_table :prediction_pts do |t|
      t.string :stats_id, null: false
      t.decimal :pt
      t.boolean :is_group, default: false
      t.timestamps
    end

    add_index :prediction_pts, :stats_id
    add_index :prediction_pts, :is_group
  end
end
