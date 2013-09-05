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

  task :fake => :environment do
    market = Market.find(25)
    contest_types = market.contest_types
    contest_type = nil
    contest_types.each do |ct|
      if ct.buy_in == 10
        contest_type = ct
        break
      end
    end
    print "contest type: #{contest_type.inspect}\n"
    #create a bunch of users and, for each user, a roster. then buy players
    #create a map[position: list of players]
    players_by_position = {}
    market.players.each do |player|
      players = players_by_position[player.position]
      if players.nil?
        players = []
        players_by_position[player.position] = players
      end
      players << player
    end

    200.times do |i|
      user = User.find_by_email("fake#{i}@fake.com")
      if user.nil?
        puts "creating user #{i} with a roster"
        user = User.create( name:     "fake",
                            provider: "fake",
                            uid:      "fake",
                            email:    "fake#{i}@fake.com",
                            password: Devise.friendly_token[0,20])
      end
      roster = user.in_progress_roster
      if roster.nil?
        roster = Roster.generate_contest_roster(user, contest_type)
      end
      if roster.players.length == 0
        puts "buying players for roster #{roster.id}"
        Positions.default_NFL.split(',').map do |position|
          player = players_by_position[position].sample
          begin
            roster.add_player(player)
          rescue Error
            puts "woops"
          end
        end
      end
      puts "roster #{roster.id} has #{roster.players.length} players"
    end

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
