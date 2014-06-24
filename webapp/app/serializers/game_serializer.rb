class GameSerializer < ActiveModel::Serializer
  attributes :id, :stats_id, :status, :game_day, :game_time, :home_team,
             :away_team, :season_type, :season_week, :season_year, :network

  def home_team
    Team.where(stats_id: object[:home_team]).first.name
  end

  def away_team
    Team.where(stats_id: object[:away_team]).first.name
  end
end
