class CreateEventPredictions < ActiveRecord::Migration
  def change
    create_table :event_predictions do |t|
      t.integer :individual_prediction_id
      t.string :event_type
      t.integer :value
      t.string :less_or_more

      t.timestamps
    end
  end
end
