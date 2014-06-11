class CreatePredictions < ActiveRecord::Migration
  def change
    create_table :predictions do |t|
      t.string  :stats_id
      t.string  :game_stats_id
      t.integer :user_id
      t.string  :sport
      t.string  :prediction_type
      t.decimal :pt
      t.timestamps
    end

    add_index :predictions, :game_stats_id
    add_index :predictions, :user_id
    add_index :predictions, :stats_id
    add_index :predictions, :prediction_type
  end
end
