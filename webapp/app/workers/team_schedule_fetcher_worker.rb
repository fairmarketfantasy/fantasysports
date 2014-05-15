class TeamScheduleFetcherWorker
  include Sidekiq::Worker

  sidekiq_options :queue => :team_schedule_fetcher

  def perform(team_stats_id)
    @team = Team.find team_stats_id

    data = JSON.parse open("http://api.sportsnetwork.com/v1/mlb/schedule?team_id=#{team_stats_id}&api_token=#{TSN_API_KEY}").read
    parse_data(data['listings'])
    #prev_season_data = JSON.parse open("http://api.sportsnetwork.com/v1/mlb/schedule?team_id=#{team_stats_id}&year=#{Time.now.year-1}&api_token=#{TSN_API_KEY}").read
    #parse_data(prev_season_data['listings'])
  end

  def self.job_name(team_stats_id)
    @team = Team.find team_stats_id
    return 'No team found' unless @team

    "Fetch team schedule for team #{@team.name}"
  end

  private

  def parse_data(data)
    data.each do |listing|
      game = Game.find(listing['game_id']) rescue Game.new
      game.stats_id = listing['game_id'].to_s
      game.home_team = Team.find_by_sport_id_and_market(@team.sport_id,listing['home_team']).stats_id
      game.away_team = Team.find_by_sport_id_and_market(@team.sport_id,listing['away_team']).stats_id
      game.game_day = Date.strptime listing['gamedate'], '%m/%d/%Y'
      Time.zone = 'Eastern Time (US & Canada)'
      game.game_time = Time.zone.parse(game.game_day.to_s + ' ' + listing['gametime']).utc
      game.status = listing['status'].present? ? listing['status'].downcase : 'scheduled'
      game.season_year = (Time.now.utc - 4).year
      game.sport = @team.sport
      begin
        game.save!
      rescue ActiveRecord::RecordNotUnique
      end
      game.create_or_update_market
    end
  end
end
