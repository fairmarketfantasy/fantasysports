class WeeklyDigest
  attr_accessor :user
  attr_accessor :deliver_at

  def initialize(attrs)
    self.user = attrs[:user]
    self.deliver_at = attrs[:deliver_at] || Time.now
  end

  def rosters
    rosters = user.rosters.joins('JOIN markets m ON rosters.market_id=m.id').where('', ).order('closed_at desc')
    rosters = rosters.over.page(1)
    rosters = rosters.select{|r| r.market.closed_at > 7.days.ago}
  end

  def markets
    week_market = Market.where(['closed_at > ? AND (closed_at - started_at > \'3 days\') AND state IN(\'published\', \'opened\', \'closed\')', Time.now]).order('closed_at asc').first
    markets =  Market.where(['closed_at > ? AND closed_at <= ?  AND state IN(\'published\', \'opened\', \'closed\')', Time.now, week_market.closed_at]).page(1).order('closed_at asc').limit(10)
    markets = markets.select{|m| m.id != week_market.id}.unshift(week_market)
  end
end
