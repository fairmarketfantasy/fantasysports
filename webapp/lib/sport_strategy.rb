class SportStrategy
  def self.for(sportName)
    Object.const_get(sportName + 'Strategy').new
  end

  def fetch_markets(type)
    raise NotImplementedError.new
  end
end

class NBAStrategy < SportStrategy
  def initialize
    @sport = Sport.where(:name => "NBA").first
  end

  def fetch_markets(type)
    if type == 'single_elimination'
      @sport.markets.where(
          "game_type IS NULL OR game_type ILIKE '%single_elimination'"
        ).where(['closed_at > ? AND state IN(\'published\', \'opened\')', Time.now.utc - 4.hours]
        ).order('closed_at asc').limit(10).select{|m| m.game_type =~ /single_elimination/ }
    else
      next_market_day = @sport.markets.where(['closed_at > ?', Time.now.utc - 4.hours]).order('closed_at asc').first.closed_at.beginning_of_day
      @sport.markets.where(
          ["game_type IS NULL OR game_type = 'regular_season'"]
          ).where(['closed_at > ? AND closed_at <= ?  AND state IN(\'published\', \'opened\')', Time.now.utc, next_market_day + 1.day + 4.hours]
          ).order('closed_at asc').limit(20)
    end
  end
end

class NFLStrategy < SportStrategy
  def initialize
    @sport = Sport.where(:name => "NFL").first
  end

  def fetch_markets(type)
    if type == 'single_elimination'
      @sport.markets.where(
          "game_type IS NULL OR game_type ILIKE '%single_elimination'"
        ).where(['closed_at > ? AND state IN(\'published\', \'opened\', \'closed\')', Time.now]
        ).order('closed_at asc').limit(10).select{|m| m.game_type =~ /single_elimination/ }
    else
      week_market = @sport.markets.where(['closed_at > ? AND name ILIKE \'%week%\' AND state IN(\'published\', \'opened\', \'closed\')', Time.now]).order('closed_at asc').first
      markets =  @sport.markets.where(
                    ["game_type IS NULL OR game_type = 'regular_season'"]
                  ).where(['closed_at > ? AND closed_at <= ?  AND state IN(\'published\', \'opened\', \'closed\')', Time.now, (week_market && week_market.closed_at) || Time.now + 1.week]
                  ).order('closed_at asc').limit(10)
      markets = markets.select{|m| m.id != week_market.id}.unshift(week_market) if week_market
      markets
    end
  end
end
