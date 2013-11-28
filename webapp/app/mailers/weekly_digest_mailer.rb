class WeeklyDigestMailer < ActionMailer::Base
  default from: "Fair Market Fantasy <no-reply@fairmarketfantasy.com>"

  def digest_email(user)
    @user = user
    mail(to: @user.email, subject: 'Your Weekly Digest')
  end
end
