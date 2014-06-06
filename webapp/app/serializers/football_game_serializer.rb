class FootballGameSerializer < ActiveModel::Serializer
  attributes :stats_id, :sport_id, :game_time, :get_home_team, :get_away_team

  def get_home_team
    get_team('home', options[:user], options[:type])
  end

  def get_away_team
    get_team('away', options[:user], options[:type])
  end

private

  def get_team(type, user, competition_type)
    team_stats_id = object.send("#{type}_team")
    team = Team.find(team_stats_id)
    {
        name: team.name,
        stats_id: team_stats_id,
        logo_url: team.logo_url,
        pt: team.pt(competition_type),
        game_stats_id: object.stats_id,
        disable_pt: Prediction.prediction_made?(team_stats_id, 'daily_wins', object.stats_id, user)
    }
  end
end
