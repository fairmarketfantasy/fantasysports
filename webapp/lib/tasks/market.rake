namespace :market do
  task :tend => :environment do
  	publish_markets
  end
end

def publish_markets
	puts "finding markets to publish"
	markets = Market.where("published_at <= ? AND (state is null or state='')", Time.now)
	puts markets
	markets.each do |market|
		ActiveRecord::Base.connection.execute("SELECT publish_market(#{market.id})")
	end
end

