class WeeklyDigestWorker

  include Sidekiq::Worker

  sidekiq_options :queue => :weekly_digest

  def perform(email)
    user = User.where(email: email).first
    email = WeeklyDigestMailer.digest_email(user)
    if email
      SentEmail.create!(:email_type => 'week_digest', :user_id => user.id, :sent_at => Time.new, :email_content => email.body.to_s)
      email.deliver
    end
  end

  def self.job_name(email)
    user = User.find_by_email(email)
    return 'no user found when sending digest email' unless user.present?
    "Send weekly digest email to #{user.name}"
  end
end

