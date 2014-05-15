class SportStrategy
  def self.for(sportName)
    Object.const_get(sportName + 'Strategy').new
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
      markets.any? && markets.first.games.first.season_type == "PST" ? markets.limit(3) : markets.limit(20)
    end
  end

  def calculate_market_points(market_id)
    market = Market.find(market_id)
    total_expected = 0
    total_bets = 0
    market.market_players.each do |mp|
      # calculate total ppg # TODO: this should be YTD
      played_games_ids = StatEvent.where("player_stats_id='#{mp.player.stats_id}' AND activity='points' AND quantity != 0" ).
                                   pluck('DISTINCT game_stats_id')
      games = Game.where(stats_id: played_games_ids)

      events = StatEvent.where(:player_stats_id => mp.player.stats_id, game_stats_id: played_games_ids, activity: 'points')
      recent_games = games.order("game_time DESC").first(5)
      # calculate ppg in last 5 games
      recent_events = events.where(game_stats_id: recent_games.map(&:stats_id))

      if events.any?
        recent_exp = (StatEvent.collect_stats(recent_events)[:points] || 0 ).to_d/recent_games.count
        total_exp = (StatEvent.collect_stats(events)[:points] || 0 ).to_d / BigDecimal.new(played_games_ids.count)
      end

      # set expected ppg
      # TODO: HANDLE INACTIVE
      if mp.player.status != 'ACT' || events.count == 0
        mp.expected_points = 0
      else
        mp.expected_points = total_exp * 0.7 + recent_exp * 0.3
      end
      total_expected += mp.expected_points
    end
    market.market_players.each do |mp|
      # set total_bets & shadow_bets based on expected_ppg/ total_expected_ppg * 30000
      mp.bets = mp.shadow_bets = mp.initial_shadow_bets = mp.expected_points.to_f / (total_expected + 0.0001) * 300000
      total_bets += mp.bets
      mp.save!
      next_market_day_end = @sport.markets.where(['closed_at > ?', Time.now.utc]).order('closed_at asc').first.closed_at + 6.hours
      this_day_end = Time.now.utc.end_of_day + 6.hours
      markets = @sport.markets.where(
          ["game_type IS NULL OR game_type = 'regular_season'"]
          ).where(['closed_at > ? AND closed_at <= ?  AND state IN(\'published\', \'opened\')', Time.now.utc, [next_market_day_end, this_day_end].min]
          ).order('closed_at asc')
      markets.any? && markets.first.games.first.season_type == "PST" ? markets.select { |m| !m.games.where("status != 'scheduled'").any? } : markets.limit(20)
    end
    market.expected_total_points = total_expected
    market.total_bets = market.shadow_bets = market.initial_shadow_bets = total_bets
    market.save!
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
  attr_accessor :positions_mapper

  def initialize
    @sport = Sport.where(:name => 'MLB').first
    @positions_mapper = { 'SP' => 'SP', 'P'=>'RP', 'RP'=>'RP', 'C'=> 'C', '1B'=> '1B/DH', '2B'=> '2B',
                         '3B'=> '3B', 'SS'=> 'SS', 'CF'=> 'OF', 'LF'=> 'OF', 'OF'=> 'OF', 'RF'=> 'OF', 'DH'=> '1B/DH', 'PH'=> '1B/DH'}
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
        recent_points = StatEvent.collect_stats(recent_events, mp.position)['Fantasy Points'.to_sym]
        last_year_points = StatEvent.collect_stats(last_year_events, mp.position)['Fantasy Points'.to_sym]
        this_year_points = StatEvent.collect_stats(this_year_events, mp.position)['Fantasy Points'.to_sym]
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
end
