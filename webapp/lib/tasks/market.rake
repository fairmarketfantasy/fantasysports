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
    CSV.open(file, "wb") do |csv|
      csv << ["INSTRUCTIONS: Do not modify the first 4 columns of this sheet.  Fill out the Desired Shadow Bets column. Save the file as a .csv and send back to us"]
      csv << ["Canonical Id", "Name", "Team", "Position", "Desired Shadow Bets"]
      market.players.each do |player|
        csv << [player.stats_id, player.name, player.team.abbrev, player.position]
      end
    end
  end

  task :import_players, [:market_id] => :environment do |t, args|
    file = File.join(Rails.root, "market_players_#{args.market_id}.csv")
    puts "Opening file: #{file}"
    market = Market.find args.market_id
    #reset market
    market.state = nil
    market.save!
    market.publish

    count = 0
    total_bets = 0
    CSV.foreach(file) do |row|
      count += 1
      next if count <= 2
      player_stats_id, shadow_bets = row[0], row[4]
      if !shadow_bets.blank?
        p = Player.where(:stats_id => player_stats_id).first
        puts "betting $#{shadow_bets} on #{p.name}"
        shadow_bets = Integer(shadow_bets) * 100
      else
        shadow_bets = 0
      end
      mp = market.market_players.where("player_stats_id = '#{player_stats_id}'").first
      mp.shadow_bets = mp.initial_shadow_bets = mp.bets = shadow_bets
      mp.save!
      total_bets += shadow_bets
    end

    #set the shadow bets to whatever they should be
    puts "\nTotal bets: $#{total_bets/100}"
    market.shadow_bets = market.total_bets = market.initial_shadow_bets = total_bets
    #TEMPORARY: artificially raise the price multiplier
    market.price_multiplier = market.market_players.size / 50
    puts "using price multiplier: #{market.price_multiplier}"
    market.save!
  end

end

