namespace :market do
  task :tend => :environment do
  	publish_markets
  	open_markets
  	close_markets
  end
end

def publish_markets
	puts "finding markets to publish"
	markets = Market.where("published_at <= ? AND (state is null or state='')", Time.now)
	puts "publishing #{markets.length} markets"
	markets.each do |market|
		ActiveRecord::Base.connection.execute("SELECT publish_market(#{market.id})")
	end
end

def open_markets
	puts "finding markets to open"
	markets = Market.where("published_at <= ? AND state = 'published'", Time.now)
	puts "opening #{markets.length} markets"
	markets.each do |market|
		ActiveRecord::Base.connection.execute("SELECT open_market(#{market.id})")
	end
end

def close_markets
	puts "finding markets to close"
	markets = Market.where("closed_at <= ? AND state = 'opened'", Time.now)
	puts "closing #{markets.length} markets"
	markets.each do |market|
		ActiveRecord::Base.connection.execute("SELECT close_market(#{market.id})")
	end

end
