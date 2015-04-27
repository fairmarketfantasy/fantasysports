class AddMarketDefaults < ActiveRecord::Migration
  def change
    create_table :market_defaults do |t|
      t.integer :sport_id, :null => false
      t.decimal :single_game_multiplier, :null => false
      t.decimal :multiple_game_multiplier, :null => false
    end
  end
end
