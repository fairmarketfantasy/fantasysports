namespace :market do

  task :tend, [:wait_time] => :environment do |t, args|
    File.open(ENV['PIDFILE'], 'w') { |f| f << Process.pid } if ENV['PIDFILE']
  	wait_time = 60
  	if not args.wait_time.nil?
  		wait_time = Integer(args.wait_time)
  	end
  	puts "Updating markets every #{wait_time} seconds"
  	while true
  		puts "#{Time.now} -- inspecting markets"
      Market.tend_all
	  	sleep wait_time
  	end
  end

  task :publish => :environment do
		Market.publish_all
  end

  task :open => :environment do
    Market.open_all
  end  

  task :lock_players => :environment do
    Market.lock_players_all
  end

  task :close => :environment do
  	Market.close_all
  end

  task :stats => :environment do
    Market.tabulate_all
  end

  task :complete => :environment do
    Market.complete_all
  end

end

