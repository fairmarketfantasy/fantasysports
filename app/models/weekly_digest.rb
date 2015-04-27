class WeeklyDigest
  attr_accessor :user, :sport, :deliver_at

  def initialize(attrs)
    self.user = attrs[:user]
    self.deliver_at = attrs[:deliver_at] || Time.now
    self.sport = attrs[:sport]
  end

  def rosters
    rosters = user.rosters.joins('JOIN markets m ON rosters.market_id=m.id').where(['m.sport_id = ?', self.sport.id]).order('closed_at desc')
    rosters = rosters.over.page(1)
    rosters = rosters.select{|r| r.market.closed_at > 7.days.ago}
  end

  def markets
    SportStrategy.for(self.sport.name).fetch_markets('regular_season')
  end
end

