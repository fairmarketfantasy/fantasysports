class MarketOrderSerializer < ActiveModel::Serializer
  attributes :id, :market_id, :roster_id, :action, :player_id, :price, :rejected, :rejected_reason, :created_at, :updated_at
end
