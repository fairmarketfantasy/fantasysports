class ContestMailer < ActionMailer::Base
  default from: "no-reply@fairmarketfantasy.com"

  def invite_to_contest(invitation, inviter, contest, email)
    @invitation = invitation
    @inviter = inviter
    @contest = contest
    subject = invitation.private_contest ?
        "#{inviter.name} invited you to their league on FairMarketFantasy.com" : "#{inviter.name} challenged you on FairMarketFantasy.com"
    envelope = {
      to: email,
      subject: subject
    }
    mail(envelope)
  end

end
