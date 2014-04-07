class GameStatFetcherWorker
  include Sidekiq::Worker

  sidekiq_options :queue => :game_stat_fetcher

  def perform(game_stat_id)
    @game = Game.find_by_stats_id game_stat_id

    @game.update_attributes({ :home_team_stats => { :points => data['home_team_score']},
                              :away_team_stats => { :points => data['home_team_score'] }})

    data = JSON.parse open("http://api.sportsnetwork.com/v1/mlb/play_by_play?game_id=#{game_stat_id}&api_token=#{TSN_API_KEY}").read

    @game.update_attributes({ :home_team_stats => {:points => data['']}})

    data['plays'].each do |d|

      d['batter'].each do |batter|

      end

      d['pitchers'].each do |pitcher|

      end

      d['pitches'].each do |pitch|

      end

      d['fielders'].each do |fielder|

      end

    end

  end

  def self.job_name(game_stat_id)
    @game = Game.find_by_stats_id game_stats_id
    return 'No team found' unless @game

    "Fetch team players for team #{@game.stats_id}"
  end
end