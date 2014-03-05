class WeeklyDigestMailer < ActionMailer::Base
  default from: "Predict That <no-reply@predictthat.com>"

  def digest_email(user)
    return nil if user.last_sent_digest_at > 6.days.ago
    @base_url = url_for controller: 'pages', action: 'index'
    @user = user
    @sport_digests = Sport.active.map do |s|
      WeeklyDigest.new(user: user, sport: s)
    end

    mail(to: @user.email, subject: 'Your Weekly Digest')
  end
end
