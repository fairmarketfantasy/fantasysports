class SportStrategy
  def self.for(sportName, category = 'fantasy_sports')
    if category == 'sports'
      NonFantasyStrategy.new(sportName)
    else
      Object.const_get(sportName + 'Strategy').new
    end
  end

  def fetch_markets(type)
    if type == 'single_elimination'
      @sport.markets.where(
          "game_type IS NULL OR game_type ILIKE '%single_elimination'"
        ).where(['closed_at > ? AND state IN(\'published\', \'opened\')', Time.now.utc]
        ).order('closed_at asc').limit(10).select{|m| m.game_type =~ /single_elimination/ }
    else
      # next_market_day = @sport.markets.where(['closed_at > ?', Time.now.utc]).order('closed_at asc').first.closed_at.beginning_of_day
      markets = @sport.markets.where(
          ["game_type IS NULL OR game_type = 'regular_season'"]
          ).where(['closed_at > ? AND closed_at <= ?  AND state IN(\'published\', \'opened\')', Time.now.utc, Time.now.utc.end_of_day + 6.hours]
          ).order('closed_at asc')
      markets = markets.any? && markets.first.games.first.season_type == "PST" ? markets.limit(3) : markets.limit(20)
      markets.select { |m| m.games.first.status == 'scheduled' }
    end
  end

  def calculate_market_points(market_id)
    market = Market.find(market_id)
    total_expected = 0
    total_bets = 0
    market.market_players.each do |mp|
      # calculate total ppg # TODO: this should be YTD
      played_games_ids = StatEvent.where("player_stats_id='#{mp.player.stats_id}' AND quantity != 0" ).
                                   pluck('DISTINCT game_stats_id')
      games = Game.where(stats_id: played_games_ids)

      events = StatEvent.where(:player_stats_id => mp.player.stats_id, game_stats_id: played_games_ids)
      recent_games = games.order("game_time DESC").first(5)
      # calculate ppg in last 5 games
      recent_events = events.where(game_stats_id: recent_games.map(&:stats_id))

      if events.any?
        recent_exp = (recent_events.map(&:point_value).reduce(:+) || 0 ).to_d/recent_games.count
        total_exp = (events.map(&:point_value).reduce(:+) || 0 ).to_d / BigDecimal.new(played_games_ids.count)
      end

      # set expected ppg
      # TODO: HANDLE INACTIVE
      if mp.player.status != 'ACT' || events.count == 0
        mp.expected_points = 0
      else
        mp.expected_points = total_exp * 0.7 + recent_exp * 0.3
      end
      total_expected += mp.expected_points
      mp.player.update_attribute(:ppg, mp.expected_points)
    end

    market.market_players.each do |mp|
      # set total_bets & shadow_bets based on expected_ppg/ total_expected_ppg * 30000
      mp.bets = mp.shadow_bets = mp.initial_shadow_bets = mp.expected_points.to_f / (total_expected + 0.0001) * 300000
      total_bets += mp.bets
      mp.save!
    end

    market.expected_total_points = total_expected
    market.total_bets = market.shadow_bets = market.initial_shadow_bets = total_bets
    market.save!
  end

  def collect_stats(events, position = nil)
    result = {}
    events.each do |event|
      key = event.activity.to_sym
      if result[key]
        result[key] += event.quantity.abs
      else
        result[key] = event.quantity.abs
      end
    end

    result
  end
end

class NonFantasyStrategy < SportStrategy
  def initialize(sport_name)
    @sport = Category.where(name: 'sports').first.sports.where(:name => sport_name).first
  end

  def fetch_markets(type)
    if type == 'single_elimination'
      @sport.markets.where(
          "game_type IS NULL OR game_type ILIKE '%single_elimination'"
      ).where(['closed_at > ? AND state IN(\'published\', \'opened\')', Time.now.utc]
      ).order('closed_at asc').limit(10).select{|m| m.game_type =~ /single_elimination/ }
    else
      # next_market_day = @sport.markets.where(['closed_at > ?', Time.now.utc]).order('closed_at asc').first.closed_at.beginning_of_day
      markets = @sport.markets.where(
          ["game_type IS NULL OR game_type = 'regular_season'"]
      ).where(['closed_at > ? AND closed_at <= ?  AND state IN(\'published\', \'opened\')', Time.now.utc, Time.now.utc.end_of_day + 6.hours]
      ).order('closed_at asc').limit(5)
    end
  end
end

class NonFantasyStrategy < SportStrategy
  def initialize(sport_name)
    @sport = Category.where(name: 'sports').first.sports.where(:name => sport_name).first
  end

  def fetch_markets(type)
    if type == 'single_elimination'
      @sport.markets.where(
          "game_type IS NULL OR game_type ILIKE '%single_elimination'"
      ).where(['closed_at > ? AND state IN(\'published\', \'opened\')', Time.now.utc]
      ).order('closed_at asc').limit(10).select{|m| m.game_type =~ /single_elimination/ }
    else
      # next_market_day = @sport.markets.where(['closed_at > ?', Time.now.utc]).order('closed_at asc').first.closed_at.beginning_of_day
      markets = @sport.markets.where(
          ["game_type IS NULL OR game_type = 'regular_season'"]
      ).where(['closed_at > ? AND closed_at <= ?  AND state IN(\'published\', \'opened\')', Time.now.utc, Time.now.utc.end_of_day + 6.hours]
      ).order('closed_at asc').limit(5)
    end
  end
end

class NBAStrategy < SportStrategy
  def initialize
    @sport = Sport.where(:name => "NBA").first
  end
end

class NFLStrategy < SportStrategy
  def initialize
    @sport = Sport.where(:name => "NFL").first
  end

  def fetch_markets(type)
    if type == 'single_elimination'
      @sport.markets.where(
          "game_type IS NULL OR game_type ILIKE '%single_elimination'"
        ).where(['closed_at > ? AND state IN(\'published\', \'opened\', \'closed\')', Time.now]
        ).order('closed_at asc').limit(10).select{|m| m.game_type =~ /single_elimination/ }
    else
      week_market = @sport.markets.where(['closed_at > ? AND name ILIKE \'%week%\' AND state IN(\'published\', \'opened\', \'closed\')', Time.now]).order('closed_at asc').first
      markets =  @sport.markets.where(
                    ["game_type IS NULL OR game_type = 'regular_season'"]
                  ).where(['closed_at > ? AND closed_at <= ?  AND state IN(\'published\', \'opened\', \'closed\')', Time.now, (week_market && week_market.closed_at) || Time.now + 1.week]
                  ).order('closed_at asc').limit(10)
      markets = markets.select{|m| m.id != week_market.id}.unshift(week_market) if week_market
      markets
    end
  end
end

class MLBStrategy < SportStrategy
  attr_accessor :positions_mapper, :price_multiplier, :sport

  def initialize
    @sport = Sport.where(:name => 'MLB').first
    @positions_mapper = { 'SP' => 'SP', 'P'=>'RP', 'RP'=>'RP', 'C'=> 'C', '1B'=> '1B/DH', '2B'=> '2B',
                         '3B'=> '3B', 'SS'=> 'SS', 'CF'=> 'OF', 'LF'=> 'OF', 'OF'=> 'OF', 'RF'=> 'OF', 'DH'=> '1B/DH', 'PH'=> '1B/DH'}
    @price_multiplier = 2.8
  end

  def calculate_market_points(market_id)
    market = Market.find(market_id)
    data = JSON.parse OpenURI.send(:open, "http://api.sportsnetwork.com/v1/mlb/pitching_probables?api_token=#{TSN_API_KEY}").read
    probable_pitcher_data = data.select { |item| item['game_id'] == market.games.first.id.to_i }.first

    if probable_pitcher_data.present?
      probable_pitcher_data['teams'].each do |t|
        next if t['pitcher_id'].blank?
        player = Player.find_by_stats_id t['pitcher_id'].to_s
        positions = PlayerPosition.where(:position => 'SP').select { |item| item.player.team.stats_id == t['team_id'].to_s }
        positions.map(&:player).flatten.each { |i| i.update_attribute(:out, true) }
        player.reload
        player.update_attribute(:out, false)

        # the case when player is in pitching probables, but don`t present in depth charts
        player.positions.create!(:position => 'SP') unless player.positions.map(&:position).include?('SP')
      end
    end

    market.market_players.destroy_all
    (Team.find(market.games.first.home_team).players.active + Team.find(market.games.first.away_team).players.active).each do |player|
      player.positions.each do |pos|
        player.update_attribute(:out, false) and next if pos.position == 'SP' && player.out? # skip not-starting SP

        market_player = market.market_players.where(:player_stats_id => player.stats_id).first || market.market_players.new # player is already added
        market_player.player = player
        market_player.expected_points = player.ppg
        market_player.shadow_bets = 0.0 # temp val
        market_player.bets = 0.0 # temp val
        market_player.player_stats_id = player.stats_id
        market_player.position = pos.position
        market_player.save!
      end
    end
    market.reload
    total_expected = 0
    market.market_players.each do |mp|
      next unless mp.position

      played_games_ids = StatEvent.where("player_stats_id='#{mp.player.stats_id}'" ).pluck('DISTINCT game_stats_id')
      games = Game.where(stats_id: played_games_ids)
      this_year_games_ids = games.where(season_year: (Time.now.utc - 4).year).pluck('DISTINCT stats_id')
      last_year_games_ids = games.where(season_year: (Time.now.utc - 4).year - 1).pluck('DISTINCT stats_id')
      recent_games = games.order("game_time DESC").first(50)
      recent_games_ids = recent_games.map(&:stats_id)
      # calculate ppg in last 5 games
      events = StatEvent.where(player_stats_id: mp.player.stats_id, game_stats_id: played_games_ids)
      last_year_events = events.where(game_stats_id: last_year_games_ids)
      this_year_events = events.where(game_stats_id: this_year_games_ids)
      recent_events = events.where(game_stats_id: recent_games_ids)
      if events.any?
        recent_points = collect_stats(recent_events, mp.position)['Fantasy Points'.to_sym]
        last_year_points = collect_stats(last_year_events, mp.position)['Fantasy Points'.to_sym]
        this_year_points = collect_stats(this_year_events, mp.position)['Fantasy Points'.to_sym]
        recent_points = recent_games.count != 0 ? (recent_points || 0).to_d/recent_games_ids.count : 0
        this_year_points = this_year_games_ids.count != 0 ? (this_year_points || 0).to_d / BigDecimal.new(this_year_games_ids.count) : 0
      end
      this_year_points ||= 0
      last_year_points ||= 0
      history = [last_year_points, 0].max + this_year_points
      # calculate total ppg # TODO: this should be YTD
      # set expected ppg
      # TODO: HANDLE INACTIVE
      mp.player.calculate_ppg
      if (mp.player.status =~ /(ACT|A|M)/).nil? || events.count == 0
        mp.expected_points = 0
      else
        mp.expected_points = mp.player.ppg || 0
      end

      mp.save!
      total_expected += mp.expected_points
    end

    total_bets = 0
    market.market_players.each do |mp|
      # set total_bets & shadow_bets based on expected_ppg/ total_expected_ppg * 30000
      mp.bets = mp.shadow_bets = mp.initial_shadow_bets = mp.expected_points.to_d / (total_expected + 0.0001) * 300000
      total_bets += mp.bets
      mp.save!
    end
    market.expected_total_points = total_expected
    market.total_bets = market.shadow_bets = market.initial_shadow_bets = total_bets
    market.save!
  end

  def collect_stats(events, position = nil)
    result = {}
    player = events.first.player if events.any?
    last_year = player && player.sport.name == 'MLB' && events.last.game.season_year == Time.now.year - 1
    events_games_count = player.total_games if last_year
    events.each do |event|
      hitters_types = ['Doubled', 'Tripled', 'Home Run',
                       'Run Batted In', 'Stolen Base']
      pitchers_types = ['Inning Pitched', 'Strike Out', 'Walked', 'Earned run', 'Wins']
      allowed_types = position && ['SP', 'RP'].include?(position) ? pitchers_types : hitters_types
      next if player.sport.name == 'MLB' && !allowed_types.include?(event.activity)

      key = ['Doubled', 'Tripled'].include?(event.activity) ? 'Extra base hits' : event.activity
      key = key.to_sym

      val = event.quantity.abs
      val = val / events_games_count if last_year
      if result[key]
        result[key] += val
      else
        result[key] = val
      end
    end

    if player && player.sport.name == 'MLB'
      result['Extra base hits'.to_sym] += result['Home Run'.to_sym] if result['Home Run'.to_sym] && result['Extra base hits'.to_sym]
      result['Fantasy Points'.to_sym] = events.map(&:point_value).reduce(0) { |value, sum| sum + value }
    end

    result['Era (earned run avg)'.to_sym] = result['Earned run'.to_sym] if result['Earned run'.to_sym]

    if last_year
      result['Fantasy Points'.to_sym] = result['Fantasy Points'.to_sym] / events_games_count
    end

    result
  end
end

class FWCStrategy < NonFantasyStrategy
  def initialize
    @sport = Sport.where(:name => 'FWC').first
  end

  def home_page_content(user = nil)
    last_date = Time.now.utc.end_of_day + 1.day
    opts = user.present? ? { user: user} : {}
    resp = {}
    daily_wins = @sport.games.where(game_time: ((Time.now.utc + 5.minutes)..last_date.end_of_day)).order(:game_time)
    daily_wins.map! { |g| FootballGameSerializer.new(g, opts.merge(type: 'daily_wins', game_stats_id: g.stats_id)) }
    resp[:daily_wins] = daily_wins if daily_wins.size > 0
    resp[:win_the_cup] = @sport.teams.map { |t| TeamSerializer.new(t, opts.merge(type: 'win_the_cup')) } if @sport.teams.any?
    resp[:win_groups] = @sport.groups.map { |g| GroupSerializer.new(g, opts.merge(type: 'win_groups')) } if @sport.groups.any?
    resp[:mvp] = @sport.players.with_flags.map { |u| PlayerSerializer.new(u, opts) } if @sport.players.any?
    resp
  end

  def create_prediction(params, user)
    if params['prediction_type'] == 'mvp'
      raise HttpException.new(402, 'Agree to terms!') unless user.customer_object.has_agreed_terms?
      raise HttpException.new(402, 'Unpaid subscription!') if !user.active_account? && !user.customer_object.trial_active?

      PlayerPrediction.create_prediction(params, user)

      {:msg => 'Player prediction submitted successfully!', :status => :ok}
    else
      {:msg => 'This prediction not supported', :status => 500}
    end
  end

  def grab_data
    DataFetcher.parse_world_cup

    url = SPORT_ODDS_API_HOST + '/SportsOddsAPI/Odds/5Dimes/SOC/Future'

    data = JSON.parse open(url).read

    #Parse players
    players_data = data.select { |d| d['Category'].include?('Golden Boot Award') }

    fwc_sport = Sport.where(:name => 'FWC').first
    players_data.each do |player_data|
      player = Player.where(name: player_data['ContestName']).first_or_initialize
      player.team = 'MVP'
      player.sport =fwc_sport
      player.name_abbr = player_data['ContestName']
      player.status = 'ACT'
      player.out = false
      player.pt = DataFetcher.get_pt_value(player_data['MoneyLine'])
      player.save!
    end

    CSV.foreach(Rails.root + 'db/players_country_map.csv') do |row|
      player = Player.find_by_name(row.first)
      next if row.join.include?('Name') or player.blank?
      player.update_attribute(:team, fwc_sport.teams.where(name: row.last).first.stats_id)
    end

    #Parse groups
    base_group = 'A'
    8.times do
      teams_data = data.select { |d| d['Category'] == "Group #{base_group} - Group Winner" }
      group = fwc_sport.groups.where(name: "Group #{base_group}").first_or_create
      teams_data.each do |team_data|
        name = team_data['ContestName']
        next if name.blank?
        team = fwc_sport.teams.where(name: name).first
        team.update_attribute(:group_id, group.id)

        #Fill prediction_pts
        prediction_pt = PredictionPt.find_by_stats_id_and_competition_type(team.stats_id, 'win_groups') || PredictionPt.new(stats_id: team.stats_id, competition_type: 'win_groups')
        prediction_pt.update_attributes!(pt: DataFetcher.get_pt_value(team_data['MoneyLine']))
      end

      base_group.succ!
    end

    #Parse team's PT
    teams_data = data.select { |d| d['Category'].eql?("Winner 2014") }
    teams_data.each do |team_data|
      name = team_data['ContestName']
      name = 'Bosnia' if team_data['ContestName'].include?('Bosnia')
      next unless Team.exists?(name: name)
      team = Team.find_by_name(name)
      prediction_pt = PredictionPt.find_by_stats_id_and_competition_type(team.stats_id, 'win_the_cup') || PredictionPt.new(stats_id: team.stats_id, competition_type: 'win_the_cup')
      prediction_pt.update_attributes!(pt: DataFetcher.get_pt_value(team_data['MoneyLine']))
    end
  end
end
