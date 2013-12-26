class AddEliminationGames < ActiveRecord::Migration
  def change
    add_column :markets, :game_type, :string
    add_column :games_markets, :finished_at, :timestamp

    add_column :markets, :salary_bonuses, :text

    add_column :games, :home_team_status, :text
    add_column :games, :away_team_status, :text

    # Unrelated but useful
    add_column :market_players, :created_at, :timestamp
    add_column :market_players, :updated_at, :timestamp
  end
end
