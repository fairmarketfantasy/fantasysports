namespace :email do
  # should take a date
  desc 'queue weekly digests for a single user'
  task :queue_digest_for_user, [:email] => :environment do |t, args|
    Resque.enqueue(WeeklyDigestWorker, args.email)
  end

  # should take a date
  desc 'queue weekly digests for all users'
  task :queue_digests => :environment do
    User.where(['((SELECT sent_at FROM sent_emails WHERE user_id=users.id AND email_type=\'week_digest\' order by sent_at desc limit 1) IS NULL AND users.created_at < now())  - interval \'3 days\') OR 
                  (SELECT sent_at FROM sent_emails WHERE user_id=users.id AND email_type=\'week_digest\' order by sent_at desc limit 1) < ?', Time.new - 1.day]).all.each do |user|
      Resque.enqueue(WeeklyDigestWorker, user.email)
    end
  end
end

