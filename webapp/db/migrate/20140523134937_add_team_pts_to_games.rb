class AddTeamPtsToGames < ActiveRecord::Migration
  def change
    add_column :games, :home_team_pt, :decimal
    add_column :games, :away_team_pt, :decimal
  end
end
