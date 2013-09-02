namespace :market do
  task :tend => :environment do
  	publish_markets
  end
end

def publish_markets
	puts "finding markets to publish"
	markets = Market.where("published_at <= ? AND (state is null or state='')", Time.now)
	print markets
	markets.each do |market|
		ActiveRecord::Base.connection.execute("SELECT publish_market(#{market.id})")
	end
end

def open_markets
	puts "finding markets to open"
	markets = Market.where("published_at <= ? AND state = 'published'", Time.now)
	if not markets.empty? then
		puts "publishing #{markets.length} markets"
		markets.each do |market|
			ActiveRecord::Base.connection.execute("SELECT open_market(#{market.id})")
		end
	end
end

