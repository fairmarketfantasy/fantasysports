namespace :email do
  # should take a date
  desc 'queue weekly digests for a single user'
  task :queue_digest_for_user, [:email] => :environment do |t, args|
    WeeklyDigestWorker.perform_async(args.email)
  end

  # should take a date
  desc 'queue weekly digests for all users'
  task :queue_digests => :environment do
    User.where(['((SELECT sent_at FROM sent_emails WHERE user_id=users.id AND email_type=\'week_digest\' order by sent_at desc limit 1) IS NULL AND users.created_at < ?) OR
                  (SELECT sent_at FROM sent_emails WHERE user_id=users.id AND email_type=\'week_digest\' order by sent_at desc limit 1) < ?', Time.now - 3.day, Time.now - 1.day]).all.each do |user|
      WeeklyDigestWorker.perform_async(args.email)
    end
  end
end

