class WeeklyDigestWorker
  @queue = :weekly_digest
  def self.perform(email)
    user = User.where(email: email).first
    WeeklyDigestMailer.digest_email(user).deliver
  end
end
