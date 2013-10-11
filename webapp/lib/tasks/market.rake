require 'csv'
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
      Market.tend
	  	sleep wait_time
  	end
  end

  task :publish => :environment do
		Market.publish
  end

  task :open => :environment do
    Market.open
  end  

  task :lock_players => :environment do
    Market.lock_players
  end

  task :close => :environment do
  	Market.close
  end

  task :stats => :environment do
    Market.tabulate
  end

  task :complete => :environment do
    Market.complete
  end

  task :dump_players, [:market_id] => :environment do |t, args|
    market = Market.find args.market_id
    file = File.join(Rails.root, "market_players_#{market.id}.csv")
    puts "Writing to file: #{file}"
    csv = market.dump_players_csv
    File.open(file, "wb") {|f| f.write(csv) }
  end

  task :import_players, [:market_id] => :environment do |t, args|
    file = File.join(Rails.root, "market_players_#{args.market_id}.csv")
    puts "Opening file: #{file}"
    market = Market.find args.market_id
    #reset market
    market.import_players_csv(file)
  end

end

