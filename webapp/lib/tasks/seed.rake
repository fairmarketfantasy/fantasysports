# namespace :seed do
#   task :nfl_data do
#     root = File.join(Rails.root, '..', 'datafetcher')
#     `GOPATH=#{root} go run #{root}/datafetcher.go -year 2013 -fetch serve`
#   end
# end

desc 'run data fetcher with given arguments'
def run_fetcher(args, compile = true)
  yaml = YAML.load_file(File.join(Rails.root, 'config', 'database.yml'))[Rails.env]
  root = File.join(Rails.root, '..', 'datafetcher')
  puts "PATH=$PATH:/usr/local/go/bin DB_HOST=#{yaml["host"]} GOPATH=#{root} go run #{compile ? '-a' : ''} #{root}/src/github.com/MustWin/datafetcher/datafetcher.go #{args}"
  `PATH=$PATH:/usr/local/go/bin DB_HOST=#{yaml["host"]} GOPATH=#{root} go run #{compile ? '-a' : ''} #{root}/src/github.com/MustWin/datafetcher/datafetcher.go #{args}`
end

namespace :seed do
  namespace :backfill do
    desc "Backfill stats for every game in this season"
    task :fill_stats_ytd => :environment do
      threadpool = ThreadPool.new(16)
      Game.where(:sport_id => Sport.where(:name => 'NBA').first, :season_type => 'REG', :season_year => 2013, :status => 'closed').each do |g|
      #  next if g.stat_events.length > 0
        run_fetcher "-year 2013 -fetch stats -sport " + g.sport.name + " -statsId " + g.stats_id, false
      end
      threadpool.shutdown
    end

    task :fix_broken_stats => :environment do
      threadpool = ThreadPool.new(16)
      ids = Roster.where(state: 'finished', score: 0).map { |r| r.market if r.market }.compact.
                                                      map(&:games).flatten.map(&:stats_id)
      games = Game.where(stats_id: ids,
                         sport_id: Sport.where(:name => 'NBA').first,
                         season_type: 'REG', :season_year => 2013,
                         status: 'closed')
      games.each do |g|
        next if g.stat_events.length > 0

        run_fetcher "-year 2013 -fetch stats -sport " + g.sport.name + " -statsId " + g.stats_id, false
      end
      threadpool.shutdown
      games.map(&:markets).flatten.map(&:id).uniq.each do |id|
        market = Market.find(id)
        market.games.each { |game| DataFetcher.update_game_players(game) }
        market.update_attribute(:state, 'closed')
        market.rosters.each do |roster|
          roster.update_attribute(:state, 'submitted') if roster.state == 'finished'
          next if roster.amount_paid.nil? || roster.state != 'submitted'

          customer_object = roster.owner.customer_object
          customer_object.monthly_contest_entries -= Roster::FB_CHARGE
          customer_object.monthly_winnings -= roster.amount_paid/1000
          customer_object.save!
        end
        market.tabulate_scores
        market.contests.each do |c|
          c.set_payouts!
          c.update_attribute(:paid_at, nil)
          c.transaction_records.where(event: ['contest_payout', 'rake']).each { |tr| tr.destroy }
        end
        market.reload
        market.individual_predictions.each do |ip|
          next if ip.state == 'canceled'

          ip.update_attribute(:state, 'submitted')
          customer_object = ip.user.customer_object
          customer_object.monthly_contest_entries -= Roster::FB_CHARGE
          customer_object.monthly_winnings -= ip.award
          customer_object.save!
        end

        market.complete
        market.reload
      end
    end
  end

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

  desc 'Run the datafetcher for all sports'
  task :data do
    run_fetcher "-year 2013 -fetch serve"
  end

  namespace :nfl do

    desc 'fetch the nfl data for the year (keeps running)'
    task :data do
      #ensure that another datafetcher task is not running
      run_fetcher "-year 2013 -fetch serve -sport NFL"
    end

    desc 'fetch the player stats for the games'
    task :player_stats_for_games => :environment do
      Game.where(["game_time < ? AND game_time > ?", Time.new, Time.new(2013)]).each do |game|
        run_fetcher "-fetch stats -sport NFL -year #{game.season_year} -season #{game.season_type} -week #{game.season_week} -away #{game.away_team} -home #{game.home_team}"
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
    bucket = s3.buckets['fairmarketfantasy.com']
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
    sports = {
      "nfl" => 'yq9uk9qu774eygre2vg2jafe',
      "nba" => '5n9kzft8ty4dhubeke29mvbb'
    }
    # NBA: 5n9kzft8ty4dhubeke29mvbb
    sports.each do |sport, key|
      headshot_manifest = "http://api.sportsdatallc.org/#{sport}-images-p1/manifests/headshot/all_assets.xml?api_key=#{key}"
      path = File.join(Rails.root, '..', 'docs', 'sportsdata', sport, 'headshots.xml')
      open(headshot_manifest) do |xml|
        File.open(path, 'w') do |f|
          f.write(xml.read)
        end
      end
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
            url = "http://api.sportsdatallc.org/nba-images-p1/headshot/#{href}?api_key=#{key}"
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

  desc 'push team logo to s3'
  task :push_team_logo_to_s3 => :environment do
    s3 = AWS::S3.new
    bucket = s3.buckets['fairmarketfantasy-prod']
    uploaded = bucket.objects.collect(&:key)
    teams = Category.where(name: 'fantasy_sports').first.sports.where(name: 'MLB').first.teams
    teams.each do |team|
      team_name = team.name.gsub('`', '').downcase
      path = Rails.root.join('app', 'assets', 'images', 'logos', "team-logos_#{team_name}.png")
      File.open(path) do |img|
        s3_key = "team-logos/mlb/#{team_name}.png"
        next if uploaded.include?(s3_key)
        puts s3_key
        begin
          bucket.objects[s3_key].write(img.read)
          bucket.objects[s3_key].acl = :public_read
          uploaded << s3_key
        rescue => e
          puts e.message
          retry
        end
      end
    end

    teams = Category.where(name: 'sports').first.sports.where(name: 'FWC').first.teams
    teams.each do |team|
      team_name = team.name.gsub(' ', '-')
      path = Rails.root.join('app', 'assets', 'images', 'flags', "#{team_name}_flat_big.png") # "#{team_name}_flat.png"
      File.open(path) do |img|
        s3_key = "team-logos/fwc/#{team_name.downcase}.png" # "team-logos/fwc/#{team_name.downcase}-small.png
        next if uploaded.include?(s3_key)
        puts s3_key
        begin
          bucket.objects[s3_key].write(img.read)
          bucket.objects[s3_key].acl = :public_read
          uploaded << s3_key
        rescue => e
          puts e.message
          retry
        end
      end
    end
  end
end
