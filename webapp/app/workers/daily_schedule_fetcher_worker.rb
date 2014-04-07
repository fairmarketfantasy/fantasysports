class DailyScheduleFetcherWorker
  include Sidekiq::Worker

  sidekiq_options :queue => :daily_schedule_fetcher

  def perform(date)
    begin
      data = JSON.parse open("http://api.sportsnetwork.com/v1/mlb/schedule/daily?gamedate=#{date.delete('-')}&api_token=#{TSN_API_KEY}").read
    rescue OpenURI::HTTPError
      DailyScheduleFetcherWorker.perform_async(Date.parse(date) + 1.day)
      raise 'No data'
    end

    season_type = data['season_type']
    gamedate = Date.parse date

    data['games'].each do |game_dat|
      game = Game.find(game_dat['game_id']) rescue Game.new
      game.stats_id = game_dat['game_id']
      game.home_team = game_dat['home_team_id']
      game.away_team = game_dat['visiting_team_id']
      game.game_day = gamedate
      game.game_time = Time.zone.parse(date + ' ' + game_dat['gametime'])
      game.status = 'scheduled'
      game.season_type = season_type
      game.save!
    end
  end

  def self.job_name(date)
    "Fetch schedule for #{date}"
  end
end