class SeasonStatsWorker
  include Sidekiq::Worker

  sidekiq_options :queue => :season_stat_worker

  EVENT_POINTS = { 'Ground Out' => 0.0,
                   'Dropped 3rd strike, batter out' => 0.0,
                   'Struck Out Looking' => 0.0,
                   'Singled' => 1.0, # Single = +1 PTs
                   'Doubled' => 2.0, # Double = +2 PTs
                   'Struck Out Swinging' => 0.0,
                   'Fly Out' => 0.0,
                   'Fouled Out' => 0.0,
                   'Advanced on dropped wild pitch' => 0.0,
                   'Home Run' => 4.0, # Home Run = +4 Pts
                   'Bunt Foul Strikeout' => 0.0,
                   'Batter reached on Fielding Error' => 0.0,
                   'Lined out' => 0.0,
                   'Singled, but batter was thrown out trying to advance to second' => 0.0,
                   'Fielder`s Choice' => 0.0,
                   'Hit By Pitch' => 1.0,
                   'Tripled' => 3.0, # 3B = 3pts,
                   'Run Batted In' => 1.0, # RBI = 1pt
                   'Run' => 1.0, # R = 1pt
                   'Walked' => 1.0, # BB = 1pt
                   'Stolen Base' => 2.0, # SB = 2pts
                   'Out' => -0.25, # Out (calculated as at bats - hits) = -.25pt
                   'none' => 0.0,
                    # and this is for pitchers
                   'Strike Out' => 1.0,
                   'Earned run' => -1.0,
                   'Inning Pitched' => 1.0,
                   'Wins' => 4.0, # W = 4pts
                   'PENALTY' => -0.5 # -.5 for a hit or walk or hbp (hit by pitch)
                }

  def perform(team_stats_id, year, season_type = 'reg')
    @team = Team.find_by_stats_id team_stats_id
    url = "http://api.sportsnetwork.com/v1/mlb/stats?team_id=#{team_stats_id}&season=#{season_type}&year=#{year}&api_token=#{TSN_API_KEY}"
    data = JSON.parse open(url).read
    game = Game.where(:sport_id => @team.sport_id, stats_id: team_stats_id + year.to_s).first
    game.stat_events.destroy_all if game # cleanup old stat
    game ||= Game.create!(status: 'closed', sport_id: Sport.where(name: 'MLB').first.id,
                                 game_day: Date.parse("#{year}-01-01"), stats_id: team_stats_id + year.to_s,
                                 home_team: team_stats_id + year.to_s,
                                 away_team: year.to_s + team_stats_id,
                                 season_year: year.to_i,
                                 game_time: Date.parse("#{year}-01-01").to_time)
    data['batting_stats'].each do |batting_stat|
      player_stats_id = batting_stat['player_id'].to_s
      total_games  = batting_stat['games']
      # hits less doubles, triples, and homeruns
      singles = batting_stat['hits'] - batting_stat['doubles'] - batting_stat['triples'] - batting_stat['homeruns']
      create_stat_event(player_stats_id, singles, game, 'Singled')
      # Second base, or double(2B) = 2pts
      create_stat_event(player_stats_id, batting_stat['doubles'], game, 'Doubled')
      # Third base, or triple(3B) = 3pts
      create_stat_event(player_stats_id, batting_stat['triples'], game, 'Tripled')
      # Home Runs(HR) = 4pts
      create_stat_event(player_stats_id, batting_stat['homeruns'], game, 'Home Run')
      # Run Batted In (RBI) = 1pt
      create_stat_event(player_stats_id, batting_stat['rbi'] + batting_stat['homeruns'], game, 'Run Batted In')
      # Runs(R) = 1pt
      create_stat_event(player_stats_id, batting_stat['runs'], game, 'Run')
      # Base On Balls(BB) or Walks (term from Wiki) = 1pt
      create_stat_event(player_stats_id, batting_stat['walks'], game, 'Walked')
      # Stolen Base (SB) = 2pts
      create_stat_event(player_stats_id, batting_stat['sb'], game, 'Stolen Base')
      # Hit By Pitch (HBP) = 1pt
      create_stat_event(player_stats_id, batting_stat['hbp'], game, 'Hit By Pitch')
      # Out (calculated as at bats - hits) = -.25pt
      create_stat_event(player_stats_id, (batting_stat['at_bats'] - batting_stat['hits']), game, 'Out')
      player = Player.where(stats_id: player_stats_id).first
      next unless player

      player.update_attribute(:total_games, player.total_games.to_i + total_games.to_i)
    end

    data['pitching_stats'].each do |pitching_stat|
      player_stats_id = pitching_stat['player_id'].to_s
      total_games = pitching_stat['appearances']

      # Win (W) = 4pts
      create_stat_event(player_stats_id, pitching_stat['wins'], game, 'Wins')
      # Earned Run (ER) = -1pt
      create_stat_event(player_stats_id, pitching_stat['earned_runs'], game, 'Earned run')
      # Strike Out (SO) = 1pt
      create_stat_event(player_stats_id, pitching_stat['total_outs'], game, 'Strike Out')
      # Inning Pitched (IP) = 1pt
      create_stat_event(player_stats_id, pitching_stat['ip'], game, 'Inning Pitched')

      # -.5 for a hit or walk or hbp (hit by pitch)
      create_stat_event(player_stats_id, pitching_stat['walks'] + pitching_stat['hits'] , game, 'PENALTY')

      player = Player.where(stats_id: player_stats_id).first

      next unless player

      player.update_attribute(:total_games, player.total_games.to_i + total_games.to_i)
    end
  end

  def self.job_name(team_stats_id, year, season_type = 'reg')
    @team = Team.find team_stats_id
    return 'No team found' unless @team

    "Fetch team stats for team: #{@team.name}, season: #{year}, season_type: #{season_type}"
  end

  private

  def create_stat_event(player_stats_id, value, game, key)
    item = StatEvent.new(player_stats_id: player_stats_id,
                         point_value: value.to_f * EVENT_POINTS[key],
                         game_stats_id: game.stats_id,
                         activity: key,
                         quantity: value,
                         points_per: EVENT_POINTS[key],
                         data: '')
    item.save!
  end
end
