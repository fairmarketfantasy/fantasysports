class ContestMailer < ActionMailer::Base
  default from: "no-reply@fairmarketfantasy.com"

  def invite_to_contest(invitation, inviter, contest, email, message)
    @invitation = invitation
    @inviter = inviter
    @contest = contest
    @message = message
    subject = contest.private? ?
        "#{inviter.name} invited you to their league on FairMarketFantasy.com" : "#{inviter.name} challenged you on FairMarketFantasy.com"
    envelope = {
      to: email,
      subject: subject
    }
    mail(envelope)
  end

end
