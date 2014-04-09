class SeasonStatsWorker
  include Sidekiq::Worker

  sidekiq_options :queue => :season_stat_worker

  def perform(team_stats_id, year, season_type = 'reg')
    @team = Team.find_by_stats_id team_stats_id
    data = JSON.parse open("http://api.sportsnetwork.com/v1/mlb/stats?team_id=#{team_stats_id}&season=#{season_type}&year=#{year}&api_token=#{TSN_API_KEY}").read

    data['batting_stats'].each do |batting_stat|
      player = Player.find_by_stats_id  batting_stat['player_id'].to_s
      next unless player
      #player.total_points += batting_stat['']*1.0 # First Base (1B) = 1pt
      player.total_points += batting_stat['doubles']*2.0  # Second base, or double(2B) = 2pts
      player.total_points += batting_stat['triples']*3.0  # Third base, or triple(3B) = 3pts
      player.total_points += batting_stat['homeruns']*4.0 # Home Runs(HR) = 4pts
      player.total_points += batting_stat['rbi']*1.0      # Run Batted In (RBI) = 1pt
      player.total_points += batting_stat['runs']*1.0     # Runs(R) = 1pt
      player.total_points += batting_stat['walks']*1.0    # Base On Balls(BB) or Walks (term from Wiki) = 1pt
      player.total_points += batting_stat['sb']*2.0       # Stolen Base (SB) = 2pts
      player.total_points += batting_stat['hbp']*1.0      # Hit By Pitch (HBP) = 1pt
      player.total_points += (batting_stat['at_bats'] - batting_stat['hits'])*-0.25 # Out (calculated as at bats - hits) = -.25pt
      player.save!
    end

    data['pitching_stats'].each do |pitching_stat|
      player = Player.find_by_stats_id  pitching_stat['player_id'].to_s
      next unless player
      player.total_points += pitching_stat['wins'].to_i*4.0       # Win (W) = 4pts
      player.total_points += pitching_stat['earned_runs']*-1.0    # Earned Run (ER) = -1pt
      player.total_points += pitching_stat['total_outs']*1.0      # Strike Out (SO) = 1pt
      player.total_points += pitching_stat['ip']*1.0              # Inning Pitched (IP) = 1pt
      player.save!
    end
  end

  def self.job_name(team_stats_id, year, season_type = 'reg')
    @team = Team.find team_stats_id
    return 'No team found' unless @team

    "Fetch team stats for team: #{@team.name}, season: #{year}, season_type: #{season_type}"
  end
end