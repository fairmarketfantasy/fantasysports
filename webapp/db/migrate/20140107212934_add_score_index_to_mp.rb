class AddScoreIndexToMp < ActiveRecord::Migration
  def change
    add_index :market_players, [:market_id, :score]
  end
end
