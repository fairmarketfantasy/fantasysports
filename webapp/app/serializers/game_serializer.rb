class GameSerializer < ActiveModel::Serializer
  attributes :id, :stats_id, :status, :game_day, :game_time, :home_team, :away_team, :season_type, :season_week, :season_year, :network

  def home_team
    Team.find(object[:home_team]).name
  end

  def away_team
    Team.find(object[:away_team]).name
  end

end
