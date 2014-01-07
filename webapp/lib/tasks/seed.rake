# namespace :seed do
#   task :nfl_data do
#     root = File.join(Rails.root, '..', 'datafetcher')
#     `GOPATH=#{root} go run #{root}/datafetcher.go -year 2013 -fetch serve`
#   end
# end

desc 'run data fetcher with given arguments'
def run_fetcher(args)
  yaml = YAML.load_file(File.join(Rails.root, 'config', 'database.yml'))[Rails.env]
  root = File.join(Rails.root, '..', 'datafetcher')
  `PATH=$PATH:/usr/local/go/bin DB_HOST=#{yaml["host"]} GOPATH=#{root} go run -a #{root}/src/github.com/MustWin/datafetcher/datafetcher.go #{args}`
end

namespace :seed do
  desc 'reload the seeds in the database'
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
    `rake db:seed`
    `rake deploy:create_oauth_client`
    `rake seed:tend_markets_once`
  end

  desc 'tend the markets once'
  task :tend_markets_once => :environment do
    Market.tend
  end

  namespace :nfl do

    desc 'fetch the nfl data for the year (keeps running)'
    task :data do
      #ensure that another datafetcher task is not running
      run_fetcher "-year 2013 -fetch serve"
    end

    desc 'fetch the player stats for the games'
    task :player_stats_for_games => :environment do
      Game.where(["game_time < ? AND game_time > ?", Time.new, Time.new(2013)]).each do |game|
        run_fetcher "-fetch stats -year #{game.season_year} -season #{game.season_type} -week #{game.season_week} -away #{game.away_team} -home #{game.home_team}"
      end
    end

    desc 'fetch the stats for the given market'
    task :market, [:market_id] =>  :environment do |t, args|
      raise "Must pass market_id" if args.market_id.nil?
      market = Market.find(Integer(args.market_id))
      market.games.each do |game|
        run_fetcher "-fetch stats -year 2013 -season #{game.season_type} -week #{game.season_week} -home #{game.home_team} -away #{game.away_team}"
      end
      market.tabulate_scores
    end
  end

  # Run data fetcher, then do this
  desc 'track benched players'
  task :setup_bench_players => :environment do
    Market.where('closed_at < ?', Time.new).order('closed_at asc').each do |m|
      m.track_benched_players
    end
  end

  desc 'put maintenance static page on s3'
  task :push_maintenance_to_s3 => :environment do
    s3 = AWS::S3.new
    bucket = s3.buckets['fairmarketfantasy-maintenance']
    Dir[Rails.root + '../maintenance/**/*'].each do |path|
      next unless File.file?(path)
      s3_key = path.split('maintenance/')[1]
      File.open(path) do |f|
        bucket.objects[s3_key].write(f.read)
      end
    end
  end

  desc 'push player headshots to s3'
  task :push_headshots_to_s3 => :environment do
    # Fetch the headshot
    headshot_manifest = "http://api.sportsdatallc.org/nfl-images-p1/manifests/headshot/all_assets.xml?api_key=yq9uk9qu774eygre2vg2jafe"
    path = File.join(Rails.root, '..', 'docs', 'sportsdata', 'nfl', 'headshots.xml')
=begin
    open(headshot_manifest) do |xml|
      File.open(path, 'w') do |f|
        f.write(xml.read)
      end
    end
=end
    s3 = AWS::S3.new
    bucket = s3.buckets['fairmarketfantasy-prod']
    uploaded = bucket.objects.collect(&:key)
    File.open(path) do |f|
      doc = Nokogiri::XML(f)
      doc.css('asset').each do |asset|
        attr = asset.attributes['player_id']
        next unless attr
        player_stats_id = attr.value
        asset.css('link').each do |link|
          href = link.attributes['href'].value # "/headshot/23c9e491-bf62-48e2-abc3-057b50dc1142/195.jpg" 
          href = href.gsub("/headshot/", "")
          s3_key = "headshots/" + player_stats_id + '/' + href.split('/')[1]
          next if uploaded.include?(s3_key)
          puts s3_key
          url = "http://api.sportsdatallc.org/nfl-images-p1/headshot/#{href}?api_key=yq9uk9qu774eygre2vg2jafe"
          open(url) do |img|
            begin
              bucket.objects[s3_key].write(img.read)
              uploaded << href
            rescue => e
              puts e.message
              retry
            end
          end
        end
      end
    end
  end
end
