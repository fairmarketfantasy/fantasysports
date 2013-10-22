class MarketSerializer < ActiveModel::Serializer
  attributes :id, :name, :shadow_bets, :shadow_bet_rate, :started_at, :opened_at, :closed_at, :sport_id, :total_bets, :state, :market_duration
  has_many :games

  def name
    if object.name.blank?
      (object.closed_at - 6.hours).strftime "%A Night Football"
    else
      "All of " + object.name
    end
  end

  def market_duration
    if object.closed_at && object.started_at
      if (object.closed_at > object.started_at + 1.day)
        'week'
      else
        'day'
      end
    end
  end
end
