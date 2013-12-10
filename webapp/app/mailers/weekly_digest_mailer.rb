class WeeklyDigestMailer < ActionMailer::Base
  default from: "Fair Market Fantasy <no-reply@fairmarketfantasy.com>"

  def digest_email(user)
    @user = user

    @rosters = @user.rosters.joins('JOIN markets m ON rosters.market_id=m.id').where('', ).order('closed_at desc')
    @rosters = @rosters.over.page(1)
    @rosters = @rosters.select{|r| r.market.closed_at > 7.days.ago}

    week_market = Market.where(['closed_at > ? AND (closed_at - started_at > \'3 days\') AND state IN(\'published\', \'opened\', \'closed\')', Time.now]).order('closed_at asc').first
    @markets =  Market.where(['closed_at > ? AND closed_at <= ?  AND state IN(\'published\', \'opened\', \'closed\')', Time.now, week_market.closed_at]).page(1).order('closed_at asc').limit(10)
    @markets = @markets.select{|m| m.id != week_market.id}.unshift(week_market)

    mail(to: @user.email, subject: 'Your Weekly Digest')
  end
end
