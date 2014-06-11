class FixGameStatsIdType < ActiveRecord::Migration
  def change
    change_column :game_predictions, :game_stats_id, :string, :null => false
  end
end
