class MarketSerializer < ActiveModel::Serializer
  attributes :id, :name, :shadow_bets, :shadow_bet_rate, :started_at, :opened_at, :closed_at, :sport_id, :total_bets, :state, :market_duration
  has_many :games

end
