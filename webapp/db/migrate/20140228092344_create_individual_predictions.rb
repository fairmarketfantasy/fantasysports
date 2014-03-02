class CreateIndividualPredictions < ActiveRecord::Migration
  def change
    create_table :individual_predictions do |t|
      t.integer :roster_player_id, :null => false
      t.string :event_type, :null => false
      t.integer :value, :null => false
      t.string :less_or_more, :null => false
      t.timestamps
    end
  end
end
