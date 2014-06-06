class CreatePlayerPrediction < ActiveRecord::Migration
  def change
    create_table :player_predictions do |t|
      t.column :user_id, :integer, :null => false
      t.column :player_id, :integer, :null => false

      t.timestamps
    end

    add_index :player_predictions, :user_id
    add_index :player_predictions, :player_id

    add_column :players, :money_line, :integer
  end
end
