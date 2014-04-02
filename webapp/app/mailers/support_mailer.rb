class SupportMailer < ActionMailer::Base
  include SendGrid
  sendgrid_category :support_mailer

  default from: "Fair Market Fantasy <no-reply@predictthat.com>"

  def support_mail(title, email, message)
    @title = title
    @email = email
    @message = message
    envelope = {
      to: 'support@predictthat.com',
      subject: "New FMF Support Request: #{@title}"
    }
    mail(envelope)
  end

end
