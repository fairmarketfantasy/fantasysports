class GameStatFetcherWorker
  include Sidekiq::Worker

  sidekiq_options :queue => :game_stat_fetcher


  # See PBP Play type doc part for MLB

  # this is the FULL mapper for batter actions
  # fetcher raises an erorr 'wrong points map'
  POINTS_MAPPER = {
      '1B' => ['Singled', 1.0], # Single = +1 PTs
      '2B' => ['Doubled', 2.0], # Double = +2 PTs
      '3B' => ['Tripled', 3.0], # 3B = 3pts,
      'BB' => ['Walked', 1.0], # BB = 1pt
      'HR' => ['Home Run', 4.0], # Home Run = +4 Pts
      'HBP' => ['Hit By Pitch', 1.0],
      'FC' => ['Fielder`s Choice', 0.0],
      'KL' => ['SO Looking', 0.0],
      'KO' => ['SO Swinging', 0.0],
      'RCHERR' => ['Reached on Fielding Error', 0.0],
      'ERR' => ['Reached on error', 0.0],
      'SAC' => ['Sacrifice bunt', 0.0],
      'DS3' => ['Dropped 3rd strike batter not out', 0.0],
      'DS3O' => ['Dropped 3rd strike, batter out', 0.0],
      'DI' => ['Defensive interference', 0.0],
      'CI' => ['Catcher interference', 0.0],
      'OBS' => ['Obstruction', 0.0],
      'SACFC' => ['Sacrifice fielder’s choice', 0.0],
      'SACERR' => ['Sacrifice reached on error', 0.0],
      'SACDP' => ['Sacrifice double play', 0.0],
      'SFERR' => ['Sacrifice fly reached on error', 0.0],
      'FCERR' => ['Fielder’s choice reached on error', 0.0],
      '1B TAG' => ['Singled, but batter was thrown out trying to advance to second', 0.0],
      '2B TAG' => ['Singled, but batter was thrown out trying to advance to third', 0.0],
      '3B TAG' => ['Singled, but batter was thrown out trying to advance to home', 0.0],
      'GND' => ['Ground Out', 0.0],
      'TAG' => ['Tagged out', 0.0],
      'LIN' => ['Lined out', 0.0],
      'FLY' => ['Fly Out', 0.0],
      'POP' => ['Pop Out', 0.0],
      'FOUL' => ['Fouled Out', 0.0],
      'FOULERR' => ['Fouled out reached on error', 0.0],
      'DP' => ['Double play', 0.0],
      'LINDP' => ['Lined into double play', 0.0],
      'RFDP' => ['Reverse forced double play', 0.0],
      'TP' => ['Triple play', 0.0],
      'IFFLY' => ['Infield fly rule', 0.0],
      'SACFLY' => ['Sacrifice fly', 0.0],
      'SAC' => ['Sacrifice bunt', 0.0],
      'SINT' => ['Spectator interference', 0.0],
      'OINT' => ['Offense interference', 0.0],
      'IBAT' => ['Illegal batter', 0.0],
      'BOX' => ['Out of batter box', 0.0],
      'BAS' => ['Basepath violation', 0.0],
      'DWP' => ['Wild pitch', 0.0],
      'DPB' => ['Advance on passed ball', 0.0],
      'DWPO' => ['Out on dropped wild pitch', 0.0],
      'DPBO' => ['Out on passed ball', 0.0],
      'CSB' => ['Strikeout looking + stolen base', 0.0],
      'SSB' => ['Strikeout swinging + stolen base', 0.0],
      'BF' => ['Bunt Foul Strikeout', 0.0],
      'RBI' => ['Run Batted In', 1.0], # RBI = 1pt
      'R' => ['Run', 1.0], # R = 1pt
      'SB' => ['Stolen Base', 2.0], # SB = 2pts
      'OUT' => ['Out', -0.25], # Out (calculated as at bats - hits) = -.25pt
      nil => ['none', 0.0],

      # and this is for pitchers
      'SO' => ['Strike Out', 1.0],
      'ER' => ['Earned run', -1.0],
      'IP' => ['Inning Pitched', 1.0],
      'W' => ['Wins', 4.0], # W = 4pts
      'PENALTY' => ['PENALTY',-0.5] # -.5 for a hit or walk or hbp (hit by pitch)
  }


  def perform(game_stat_id)
    game = Game.find_by_stats_id game_stat_id

    return if game.stat_events.any?
    data = JSON.parse open("http://api.sportsnetwork.com/v1/mlb/play_by_play?game_id=#{game_stat_id}&api_token=#{TSN_API_KEY}").read

    game.update_attributes({:home_team_status => {:points => data['home_team_score']}.to_json,
                            :away_team_status => {:points => data['away_team_score']}.to_json})

    data['plays'].each do |d|

      batter = d['batter']

      if batter['action'].present?
        if POINTS_MAPPER[batter['action']].nil?
          puts "wrong points map for #{batter['action']}"
        else
          find_or_create_stat_event(batter['batter_id'].to_s, game, batter['action'], 1.0)
          if (batter['action'] =~ /(1B|2B|3B|HR|BB|HBP)/)
            find_or_create_stat_event(batter['pitcher_id'].to_s, game, 'PENALTY', 1.0)
          end
        end
      end


      d['pitchers'].each do |pitcher|
        find_or_create_stat_event(batter['pitcher_id'].to_s, game, 'OUT', pitcher['outs'].to_f)
      end

      # select last pitch of the inning - stats for the inning are cumulative
      pitch = d['pitches'].last
      if pitch.present?

        find_or_create_stat_event(pitch['pitcher_id'].to_s, game, 'ER', pitch['balls'].to_f)
        find_or_create_stat_event(pitch['pitcher_id'].to_s, game, 'SO', pitch['strikes'].to_f)
        # if inning pitched
        if pitch['balls'].to_i == 0
          find_or_create_stat_event(pitch['pitcher_id'].to_s, game, 'IP', 1.0)
        end
      end

    end
  end

  def self.job_name(game_stat_id)
    game = Game.find_by_stats_id game_stat_id
    return 'No team found' unless game

    "Fetch team players for team #{game.stats_id}"
  end

  private

  def find_or_create_stat_event(player_stats_id, game, action, quantity)

    st = game.stat_events.where(:player_stats_id => player_stats_id, :activity => POINTS_MAPPER[action][0]).first || game.stat_events.new
    st.player_stats_id = player_stats_id
    st.quantity = st.quantity.to_f + quantity
    st.points_per = POINTS_MAPPER[action][1]
    st.point_value = st.point_value.to_f + POINTS_MAPPER[action][1]
    st.activity = POINTS_MAPPER[action][0]
    st.data = ''
    st.save!
  end
end
