class IndividualPredictionSerializer < ActiveModel::Serializer
  attributes :id, :player_id, :market_name, :event_predictions
  has_many :event_predictions

  def market_name
    object.roster.market.name
  end

end
