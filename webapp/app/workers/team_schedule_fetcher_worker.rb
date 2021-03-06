class TeamScheduleFetcherWorker
  include Sidekiq::Worker

  sidekiq_options :queue => :team_schedule_fetcher

  def perform(team_stats_id)
    @team = Team.where(stats_id: team_stats_id).first

    data = JSON.parse open("http://api.sportsnetwork.com/v1/mlb/schedule?team_id=#{team_stats_id}&api_token=#{TSN_API_KEY}").read
    parse_data(data['listings'])
    #prev_season_data = JSON.parse open("http://api.sportsnetwork.com/v1/mlb/schedule?team_id=#{team_stats_id}&year=#{Time.now.year-1}&api_token=#{TSN_API_KEY}").read
    #parse_data(prev_season_data['listings'])
  end

  def self.job_name(team_stats_id)
    @team = Team.where(stats_id: team_stats_id).first
    return 'No team found' unless @team

    "Fetch team schedule for team #{@team.name}"
  end

  private

  def parse_data(data)
    data.each do |listing|
      game = Game.where(stats_id: listing['game_id'].to_s).first_or_initialize
      old_time = game.game_time.try(:clone)

      game.stats_id = listing['game_id'].to_s
      game.home_team = Team.find_by_sport_id_and_market(@team.sport_id,listing['home_team']).stats_id
      game.away_team = Team.find_by_sport_id_and_market(@team.sport_id,listing['away_team']).stats_id
      game.game_day = Date.strptime(listing['gamedate'], '%m/%d/%Y').to_time.utc.to_date
      Time.zone = 'Eastern Time (US & Canada)'
      game.game_time = Time.zone.parse(game.game_day.to_s + ' ' + listing['gametime']).utc
      game.status = listing['status'].present? ? listing['status'].downcase : 'scheduled'
      game.status = 'closed' if game.status == 'final'
      game.markets.each { |i| i.update_attribute(:state,nil) } if game.game_time != old_time and (old_time.is_a?(Time) and old_time.today?)
      game.season_year = (Time.now.utc - 4).year
      game.sport = @team.sport
      game.save!
      game.create_or_update_market
    end
  end
end
