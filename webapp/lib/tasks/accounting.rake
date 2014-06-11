namespace :users do
  desc 'Do user accounting'
  task :do_accounting, [:wait_time] => :environment do |t, args|
    File.open(ENV['PIDFILE'], 'w') { |f| f << Process.pid } if ENV['PIDFILE']
  	wait_time = 1.day
  	if not args.wait_time.nil?
  		wait_time = Integer(args.wait_time)
  	end
  	puts "Checking for new month every #{wait_time} seconds"
    CustomerObject.monthly_accounting!
  	while true
      day = Time.new.day
  		print "Is it a new month? Day == #{day} - "
      if day == 1
  		  puts "Yup.  Performing accounting."
        CustomerObject.monthly_accounting!
      else
  		  puts "Nope. Sleeping."
      end
	  	sleep wait_time
  	end
  end

  desc 'Recalculate users winnings'
  task :recalculate_winnings => :environment do
    User.all.each do |user|
      time = user.customer_object.trial_started_at || Time.now.beginning_of_month
      time = user.customer_object.last_activated_at if user.customer_object.last_activated_at && user.customer_object.trial_started_at && user.customer_object.trial_started_at < Time.now.beginning_of_month - 1.month

      ip = user.individual_predictions.where("state not in ('canceled', 'submitted') AND created_at > ?", time)
      r = user.rosters.where("state not in ('in_progress', 'submitted', 'cancelled') AND created_at > ?", time)
      gr = user.game_rosters.where("state = 'finished' AND created_at > ?", time)
      gp = user.game_predictions.where("game_roster_id IS NULL AND state = 'finished' AND created_at > ?", time)
      number = ip.count + r.count + gr.count + gp.count
      co = user.customer_object
      co.monthly_entries_counter = number
      co.monthly_contest_entries = number * 1.5.to_d
      sum = r.map(&:amount_paid).compact.reduce(0) { |sum, v| sum + v }
      sum += ip.map(&:award).compact.reduce(0) { |sum, v| sum + v * 100 }
      sum += gr.map(&:amount_paid).compact.reduce(0) { |sum, v| sum + v }
      sum += gp.map(&:award).compact.reduce(0) { |sum, v| sum + v * 100 }
      co.monthly_winnings = sum
      co.save!
    end
  end
end
