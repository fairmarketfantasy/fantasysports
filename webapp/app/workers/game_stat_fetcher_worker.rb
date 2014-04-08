class GameStatFetcherWorker
  include Sidekiq::Worker

  sidekiq_options :queue => :game_stat_fetcher

  POINTS_MAPPER = {
      'GND' => 0.0,
      'DS3O' => 0.0,
      'KL' => 0.0,
      '1B' => 3.0, # Single = +3 PTs
      'BB' => 0.0,
      '2B' => 5.0, # Double = +5 PTs
      'KO' => 0.0,
      'FLY' => 0.0,
      'FOUL' => 0.0,
      'DWP' => 0.0,
      'HR' => 0.0,
      'BF' => 0.0,
      'RCHERR' => 0.0,
      'LIN' => 0.0,
      '1B TAG' => 0.0,
      'FC' => 0.0,
      'HBP' => 0.0,
      nil => 0.0
  }

  def perform(game_stat_id)
    @game = Game.find_by_stats_id game_stat_id

    data = JSON.parse open("http://api.sportsnetwork.com/v1/mlb/play_by_play?game_id=#{game_stat_id}&api_token=#{TSN_API_KEY}").read

    @game.update_attributes({ :home_team_status => { :points => data['home_team_score']}.to_json,
                              :away_team_status => { :points => data['away_team_score'] }.to_json })

    # list of actions:
    # ["GND", "DS3O", "KL", "1B", "BB", "2B", "KO", "FLY", "FOUL", "DWP",
    # "HR", "BF", "RCHERR", "LIN", "", "1B TAG", "FC", "HBP"]

    data['plays'].each do |d|

      batter = d['batter']


      player = Player.find_by_stats_id(batter['batter_id'])
      player.total_point += POINTS_MAPPER[batter['action']]

      raise 'wrong points map' if POINTS_MAPPER[batter['action']].nil?

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