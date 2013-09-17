# namespace :seed do
#   task :nfl_data do
#     root = File.join(Rails.root, '..', 'datafetcher')
#     `GOPATH=#{root} go run #{root}/datafetcher.go -year 2013 -fetch serve`
#   end
# end


def run_fetcher(args)
  root = File.join(Rails.root, '..', 'datafetcher')
  `PATH=$PATH:/usr/local/go/bin GOPATH=#{root} go run #{root}/src/github.com/MustWin/datafetcher/datafetcher.go #{args}`
end

namespace :seed do
  task :reload do
    `rake db:drop`
    `rake db:create`
    # IF YOU WANT TO RECREATE THIS FILE, DO IT LIKE THIS:
    # 1) create a fresh db
    # 2) run migrations
    # 3) run the datafetcher for whatever things you need: markets, game play by plays, multiple sports, whatever
    # 4) DUMP THE SQL BEFORE TENDING MARKETS. KTHX.
    ActiveRecord::Base.load_sql_file File.join(Rails.root, 'db', 'reload.sql')
    `rake db:migrate`
    `rake db:setup_functions`
    `rake seed:tend_markets_once`
  end

  task :tend_markets_once => :environment do
    Market.tend_all
  end

  namespace :nfl do

    task :data do
      #ensure that another datafetcher task is not running
      run_fetcher "-year 2013 -fetch serve"
    end

    task :market, [:market_id] =>  :environment do |t, args|
      raise "Must pass market_id" if args.market_id.nil?
      market = Market.find(Integer(args.market_id))
      market.games.each do |game|
        run_fetcher "-fetch stats -year 2013 -season #{game.season_type} -week #{game.season_week} -home #{game.home_team} -away #{game.away_team}"
      end
      market.tabulate_scores
    end
  end
end
