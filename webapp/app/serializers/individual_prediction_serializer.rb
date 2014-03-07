class IndividualPredictionSerializer < ActiveModel::Serializer
  attributes :id, :player_id, :market_name, :event_predictions, :player_name,
             :pt, :award
  has_many :event_predictions

  def market_name
    Market.find(object.market_id).name
  end

  def player_name
    Player.find(object.player_id).name
  end
end
