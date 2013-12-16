class BlockedEmail
  def deliver! # Noop
  end
end
class ContestMailer < ActionMailer::Base
  default from: "Fair Market Fantasy <no-reply@fairmarketfantasy.com>"

  def invite_to_contest(invitation, inviter, contest, email, message)
    return BlockedEmail.new if EmailUnsubscribe.has_unsubscribed?(email, 'all') # TODO: generalize this, put it in mail.deliver?
    @invitation = invitation
    @email = email
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
