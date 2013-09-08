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
	  	publish_markets
	  	open_markets
	  	close_markets
	  	sleep wait_time
  	end
  end

  task :publish => :environment do
  	publish_markets
  end

  task :open => :environment do
  	open_markets
  end

  task :close => :environment do
  	close_markets
  end
end

def publish_markets
	markets = Market.where("published_at <= ? AND (state is null or state='')", Time.now)
	markets.each do |market|
		puts "#{Time.now} -- publishing market #{market.id}"
    market.publish
  end

end

def open_markets
	markets = Market.where("state = 'published'")
	markets.each do |market|
		puts "#{Time.now} -- opening market #{market.id}"
    market.open
	end
end

def close_markets
	markets = Market.where("closed_at <= ? AND state = 'opened'", Time.now)
	markets.each do |market|
		puts "#{Time.now} -- closing market #{market.id}"
    market.close
	end

end
