class RenameGamesPredictionFields < ActiveRecord::Migration
  def change
    rename_column :game_predictions, :game_id, :game_stats_id
    rename_column :game_predictions, :team_id, :team_stats_id
  end
end
