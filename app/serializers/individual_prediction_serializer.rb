class IndividualPredictionSerializer < ActiveModel::Serializer
  attributes :id, :player_id, :player_stat_id, :market_name, :event_predictions,
             :player_name, :pt, :award, :state, :game_time, :game_day, :game_result
  has_many :event_predictions

  def market_name
    Market.find(object.market_id).name
  end

  def player_name
    Player.find(object.player_id).name
  end

  def player_stat_id
    Player.find(object.player_id).stats_id
  end

  def game_time
    object.market.closed_at + 5.minutes
  end

  def game_day
    object.market.closed_at
  end

  def award
    object.award.to_f.round(2)
  end
end
