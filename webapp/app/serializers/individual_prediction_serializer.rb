class IndividualPredictionSerializer < ActiveModel::Serializer
  attributes :id, :player_id, :market_name, :event_predictions, :player_name
  has_many :event_predictions

  def market_name
    object.roster.market.name
  end

  def player_name
    Player.find(object.player_id).name
  end
end
