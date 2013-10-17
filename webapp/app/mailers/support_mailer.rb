class SupportMailer < ActionMailer::Base
  default from: "Fair Market Fantasy <no-reply@fairmarketfantasy.com>"

  def support_mail(title, email, message)
    @title = title
    @email = email
    @message = message
    envelope = {
      to: 'fantasysports@mustw.in',
      subject: "New FMF Support Request: #{@title}"
    }
    mail(envelope)
  end

end
