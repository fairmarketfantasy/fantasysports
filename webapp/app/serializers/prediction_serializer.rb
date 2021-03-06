class PredictionSerializer < ActiveModel::Serializer
  attributes :id, :market_name, :player_name, :game_time, :game_day, :game_result,
             :pt, :current_pt, :trade_message, :award, :state, :show_trade

  def market_name
    object.prediction_type.gsub('_', ' ').upcase
  end

  def player_name
    if object.prediction_type.eql?('mvp')
      player = Player.where(stats_id: object.stats_id).first || Player.where(id: object.stats_id).first
      player.nil? ? '' : player.name
    else
      team = Team.where(stats_id: object.stats_id).first
      team.nil? ? '' : team.name
    end
  end

  def game_time
    Game.exists?(stats_id: object.game_stats_id) ? Game.find_by_stats_id(object.game_stats_id).game_time : ''
  end

  def game_day
    Game.exists?(stats_id: object.game_stats_id) ? Game.find_by_stats_id(object.game_stats_id).game_day  : ''
  end

  def game_result
    object.result
  end

  def show_trade
    !!current_pt and !Prediction.team_plays?(object.stats_id, object.prediction_type) and current_pt.try(:round) > 15
  end

  def award
    object.award.to_f.round(2)
  end

  # CHOOSE THE GAME
  # game = Game.where(stats_id: object.game_stats_id).first
  # if not game.nil?
  #   home_team = Team.where(stats_id: game.home_team).first
  #   away_team = Team.where(stats_id: game.away_team).first
  #   "#{home_team.name}@#{away_team.name}"
  # else
  #   team = Team.where(stats_id: object.stats_id).first
  #   team.nil? ? '' : team.name
  # end

  def trade_message
    "You can trade this prediction and return #{object.pt_refund} fanbucks."
  end
end
