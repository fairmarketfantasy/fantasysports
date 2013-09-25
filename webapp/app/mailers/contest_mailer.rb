class ContestMailer < ActionMailer::Base
  default from: "no-reply@fairmarketfantasy.com"

  def invite(invitation, email)
    @invitation = invitation
    subject = invitation.contest.private? ? 
        "#{inviter.name} invited you to their league on FairMarketFantasy.com" : "#{inviter.name} challenged you on FairMarketFantasy.com"
    envelope = {
      to: email,
      subject: subject
    }
    mail(envelope)
  end

end
