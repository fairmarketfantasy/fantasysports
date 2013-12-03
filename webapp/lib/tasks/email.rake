namespace :email do
  # should take a date
  task :queue_digest_for_user, [:email] => :environment do |t, args|
    user = User.first(email: args.email)
    # TODO: use task queue
    WeeklyDigestMailer.digest_email(user)
  end

  # should take a date
  task :queue_digests => :environment do
    User.all.each do |user|
      # TODO: use task queue
      WeeklyDigestMailer.digest_email(user)
    end
  end
end
