class GamePredictionSerializer < ActiveModel::Serializer
  attributes :id, :pt, :team_name, :game_time, :game_day, :home_team_name,
             :away_team_name, :market_name, :player_name, :state, :award,
             :game_stats_id, :home_team, :opposite_team, :team_logo,
             :team_stats_id, :position_index, :game_result, :current_pt,
             :trade_message, :stats_id, :name, :logo_url, :is_home

  def team_name
    Team.where(stats_id: object.team_stats_id).first.name
  end

  def game_time
    object.game.game_time
  end

  def home_team_name
    id = object.game.home_team
    Team.where(stats_id: id).first.name
  end

  def away_team_name
    id = object.game.away_team
    Team.where(stats_id: id).first.name
  end

  def game_day
    object.game.game_day
  end

  def market_name
    home_team_name + ' @ ' + away_team_name
  end

  # maps to choice coulmn in HTML
  def player_name
    team_name
  end

  def home_team
    object.team_stats_id == object.game.home_team
  end

  def opposite_team
    object.game.teams.where.not(:stats_id => object.team_stats_id).first.name
  end

  def trade_message
    "You can trade this prediction and return #{object.pt_refund} fanbucks."
  end

  def stats_id
    object.team_stats_id
  end

  def name
    team_name
  end

  def logo_url
    object.team_logo
  end

  def is_home
    home_team
  end

  def trade_message
    "You can trade this prediction and return #{object.pt_refund} fanbucks."
  end
end
