class WeeklyDigestMailer < ActionMailer::Base
  default from: "Fair Market Fantasy <no-reply@fairmarketfantasy.com>"

  def digest_email(user)
    @base_url = url_for controller: 'pages', action: 'index'
    @user = user
    weekly_digest = WeeklyDigest.new(user: user)
    @rosters = weekly_digest.rosters
    @markets = weekly_digest.markets

    mail(to: @user.email, subject: 'Your Weekly Digest')
  end
end