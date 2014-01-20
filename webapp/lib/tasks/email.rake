namespace :email do
  # should take a date
  desc 'queue weekly digests for a single user'
  task :queue_digest_for_user, [:email] => :environment do |t, args|
    Resque.enqueue(WeeklyDigestWorker, args.email)
  end

  # should take a date
  desc 'queue weekly digests for all users'
  task :queue_digests => :environment do
    User.all.each do |user|
      Resque.enqueue(WeeklyDigestWorker, user.email)
    end
  end
end
