class FootballGameSerializer < ActiveModel::Serializer
  attributes :stats_id, :sport_id, :game_time, :get_home_team, :get_away_team

  def get_home_team
    get_team('home', options)
  end

  def get_away_team
    get_team('away', options)
  end

private

  def get_team(type, options)
    team_stats_id = object.send("#{type}_team")
    team = Team.find(team_stats_id)
    {
        name: team.name,
        stats_id: team_stats_id,
        logo_url: team.logo_url,
        pt: team.pt(options.merge(game_stats_id: object.stats_id)),
        game_stats_id: object.stats_id,
        disable_pt: Prediction.prediction_made?(team_stats_id, 'daily_wins', object.stats_id, options[:user])
    }
  end
end
