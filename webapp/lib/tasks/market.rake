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
      lock_players
      close_markets
      tabulate_scores
      complete_markets
	  	sleep wait_time
  	end
  end

  task :publish => :environment do
  	publish_markets
  end

  task :open => :environment do
    open_markets
  end  

  task :lock_players => :environment do
    lock_players
  end

  task :close => :environment do
  	close_markets
  end

  task :stats => :environment do
    tabulate_scores
  end

  task :complete => :environment do
    complete_markets
  end

end

def publish_markets
	markets = Market.where("published_at <= ? AND (state is null or state='')", Time.now)
	markets.each do |market|
		puts "#{Time.now} -- publishing market #{market.id}"
    market = market.publish
    if market.state == 'published'
      market.add_default_contests
    end
  end
end

def tabulate_scores
  Market.where("state in ('published', 'open', 'closed')").find_each do |market|
    puts "#{Time.now} -- tabulating scores for market #{market.id}"
    market.tabulate_scores
  end
end

def open_markets
	markets = Market.where("state = 'published'")
	markets.each do |market|
		puts "#{Time.now} -- opening market #{market.id}"
    market = market.open
    if market.state = 'opened'
      market.notify_market_open_event
    end
	end
end

def lock_players
  markets = Market.where("state = 'opened'")
  markets.each do |market|
    puts "#{Time.now} -- locking players in market #{market.id}"
    market.lock_players
  end
end

def close_markets
	markets = Market.where("closed_at <= ? AND state = 'opened'", Time.now)
	markets.each do |market|
		puts "#{Time.now} -- closing market #{market.id}"
    market.close
	end
end

def complete_markets
  Market.where("state = 'closed'").joins(:games).where("status='closed'").each do |market|
    puts "#{Time.now} -- completing market #{market.id}"
    market.complete
  end
end
