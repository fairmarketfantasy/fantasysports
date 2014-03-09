class IndividualPredictionSerializer < ActiveModel::Serializer
  attributes :id, :player_id, :player_stat_id, :market_name, :event_predictions,
             :player_name, :pt, :award
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
end
