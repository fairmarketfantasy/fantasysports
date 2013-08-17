class MarketSerializer < ActiveModel::Serializer
  attributes :id, :name, :shadow_bets, :shadow_bet_rate, :opened_at, :closed_at, :sport_id, :total_bets
end
