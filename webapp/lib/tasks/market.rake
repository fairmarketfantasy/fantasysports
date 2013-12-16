require 'csv'
namespace :market do

  desc 'tend the markets repeatedly'
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

  desc 'pubilsh the markets'
  task :publish => :environment do
		Market.publish
  end

  desc 'open the markets'
  task :open => :environment do
    Market.open
  end  

  desc 'lock the players'
  task :lock_players => :environment do
    Market.lock_players
  end

  desc 'close the markets'
  task :close => :environment do
  	Market.close
  end

  desc 'tabulate market stats'
  task :stats => :environment do
    Market.tabulate
  end

  desc 'complete the market'
  task :complete => :environment do
    Market.complete
  end

  desc 'dump the players to csv file'
  task :dump_players, [:market_id] => :environment do |t, args|
    market = Market.find args.market_id
    file = File.join(Rails.root, "market_players_#{market.id}.csv")
    puts "Writing to file: #{file}"
    csv = market.dump_players_csv
    File.open(file, "wb") {|f| f.write(csv) }
  end

  desc 'import the players from csv file'
  task :import_players, [:market_id] => :environment do |t, args|
    file = File.join(Rails.root, "market_players_#{args.market_id}.csv")
    puts "Opening file: #{file}"
    market = Market.find args.market_id
    #reset market
    market.import_players_csv(file)
  end

end

