class TeamScheduleFetcherWorker
  include Sidekiq::Worker

  sidekiq_options :queue => :team_schedule_fetcher

  def perform(team_stats_id)
    @team = Team.find team_stats_id

    data = JSON.parse open("http://api.sportsnetwork.com/v1/mlb/schedule?team_id=#{team_stats_id}&api_token=#{TSN_API_KEY}").read
    data['listings'].each do |listing|
      game = Game.find(listing['game_id']) rescue Game.new
      game.stats_id = listing['game_id'].to_s
      game.home_team = Team.find_by_sport_id_and_market(872,listing['home_team']).stats_id
      game.away_team = Team.find_by_sport_id_and_market(872,listing['away_team']).stats_id
      game.game_day = Date.strptime listing['gamedate'], '%m/%d/%Y'
      game.game_time = Time.zone.parse(game.game_day.to_s + ' ' + listing['gametime'])
      game.status = listing['status'].present? ? listing['status'] : 'scheduled'
      game.sport = @team.sport
      game.save!
      game.create_market unless game.markets.any?
    end
  end

  def self.job_name(team_stats_id)
    @team = Team.find team_stats_id
    return 'No team found' unless @team

    "Fetch team schedule for team #{@team.name}"
  end
end