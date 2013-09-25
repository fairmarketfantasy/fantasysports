class ContestMailer < ActionMailer::Base
  default from: "change-me-in-contest_mailer.rb@pleasechange.com"

  def invite(contest, email)
    @code = contest.invitation_code
    @contest = contest
    @owner   = contest.owner
    envelope = {
      to: email,
      subject: "Invitation from #{contest.owner.name} to join this contest."
    }
    mail(envelope)
  end

end