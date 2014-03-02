class WeeklyDigestWorker
  @queue = :weekly_digest

  def self.perform(email)
    user = User.where(email: email).first
    email = WeeklyDigestMailer.digest_email(user)
    if email
      SentEmail.create!(:email_type => 'week_digest', :user_id => user.id, :sent_at => Time.new, :email_content => email.body.to_s)
      email.deliver
    end
  end
end

