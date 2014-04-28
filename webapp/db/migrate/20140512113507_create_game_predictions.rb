class CreateGamePredictions < ActiveRecord::Migration
  def change
    create_table :game_predictions do |t|
      t.integer :user_id, :null => false
      t.integer :game_id, :null => false
      t.string :team_id, :null => false
      t.decimal :award
      t.decimal :pt
      t.string :state, :default => 'in_progress'

      t.timestamps
    end
  end
end
