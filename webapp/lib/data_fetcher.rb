class DataFetcher
  require 'nokogiri'

  NBA_BASE_URL = "http://api.sportsdatallc.org/nba-p3/"
  NBA_API_KEY_PARAMS = "?api_key=8uttxzxefmz45ds8ckz764vr"

  class << self

    def update_benched
      puts "Update benched players"
      url = NBA_BASE_URL + "league/injuries.xml" + NBA_API_KEY_PARAMS
      xml = get_xml(url)
      players = xml.search("player")
      benched_ids = []
      players.each do |node|
        id = node.xpath("@id").first.value
        status = node.at('injury').at_xpath("@status").value
        benched_ids << id if status =~ /^Out/
      end

      sport_id = Sport.where(name: 'NBA').first.id
      Player.where(stats_id: benched_ids, sport_id: sport_id).each do |player|
        player.update_attribute(:out, true) unless player.out
      end
    end

    def update_game_players(game, required_time = nil)
      return if game.sport.name == 'MLB'

      puts "Update game players"
      url = NBA_BASE_URL + "games/#{game.stats_id}/summary.xml" + NBA_API_KEY_PARAMS
      xml = get_xml(url)
      second_half_started = xml.search("quarter").find { |node| node.at_xpath("@number").value == "3" }
      return unless second_half_started

      benched_ids = []
      game_player_ids = []
      players = xml.search("player")
      players.each do |node|
        id = node.xpath("@id").first.value
        game_player_ids << id
        played = node.at_xpath("@played")

        benched_ids << id if played.nil? || played.value != "true" || less_then_n_min(node, required_time)
      end

      return if (game_player_ids.sort - benched_ids.sort).empty?
      game.players.each do |player|
        if benched_ids.include?(player.stats_id) || !game_player_ids.include?(player.stats_id)
          player.update_attribute(:out, true) unless player.out
        else
          player.update_attribute(:out, false) if player.out
        end
      end

      game.update_attribute(:checked, true)
    end

    def calculate_teams_pt(game)
      url = 'http://97.74.80.137/SportsOddsAPI/Odds/5Dimes/MLB'
      odds = JSON.parse open(url).read
      odd = odds.find do |odd|
        game.game_time == DateTime.strptime(odd["GameTime"], '%m/%d/%Y %l:%M %p')
        game.home_team == find_team(odd["Home"]).stats_id
        game.away_team == find_team(odd["Visitor"]).stats_id
      end

      return unless odd

      home_ml = odd["HomeMoneyLine"].to_d
      away_ml = odd["VisitorMoneyLine"].to_d
      game.home_team_pt = DataFetcher.get_pt_value(home_ml, away_ml)
      game.away_team_pt = DataFetcher.get_pt_value(away_ml, home_ml)
      game.save!
    end

    def parse_world_cup
      sport_id = Sport.where(name: "FWC").first.id
      year = Time.current.year
      fwc_duration = "06-01-#{year}/09-01-#{year}"
      odds = JSON.load open(WORLD_CUP_API_URL + fwc_duration)
      odds.each do |odd|
        if odd['Category'].eql? 'International World Cup 2014'
          #Fill teams
          home_name    = odd['Home'].split(/[()]/)
          visitor_name = odd['Visitor'].split(/[()]/)
          team_ids = []
          [home_name, visitor_name].each do |name|
            team_label = name.first.rstrip
            team_label = 'Bosnia' if name.first.rstrip.include?('Bosnia')
            stat_id = Digest::MD5.hexdigest(team_label)
            relation = Team.where(name: team_label, abbrev: team_label, sport_id: sport_id, market: 'World Cup')
            team = relation.first || relation.where(stats_id: stat_id).create!
            team_ids << team.stats_id
          end

          #Fill games
          game_time = DateTime.strptime(odd["GameTime"], '%m/%d/%Y %l:%M %p') + 4.hours # Brasilia timezone difference
          home_ml = odd['HomeMoneyLine'].to_d
          away_ml = odd['VisitorMoneyLine'].to_d
          game_stats_id = Digest::MD5.hexdigest(team_ids.join + odd['GameTime'])
          game = Game.where(game_day:    game_time.strftime("%Y-%m-%d"),
                            home_team:   team_ids.first,
                            away_team:   team_ids.last,
                            stats_id:    game_stats_id,
                            season_type: 'REG',
                            sport_id:    sport_id).first_or_initialize

          game.game_time        = game_time
          game.home_team_pt     = get_dayly_wins_pt(home_ml, away_ml)
          game.away_team_pt     = get_dayly_wins_pt(away_ml, home_ml)
          game.home_team_status = odd['HomeScore']
          game.away_team_status = odd['VisitorScore']
          game.status           = 'scheduled'
          game.save!

          #Process predictions for daily_wins
          Prediction.process_prediction(game, 'daily_wins') if (game_time.utc + 4.hours) < Time.now.utc
        end
      end
    end

    def find_team(team_name)
      category = Category.where(name: 'fantasy_sports').first
      sport = Sport.where(name: 'MLB', category_id: category.id).first
      team = Team.where(sport_id: sport.id, market: team_name).first
      team ||= Team.where(sport_id: sport.id).find do |t|
        t.name.downcase.include?(team_name.split(/\s+/).last.downcase)
      end

      team ||= Team.where(sport_id: sport.id).find do |t|
        t.market.downcase.include?(team_name.split(/\s+/).first.downcase)
      end

      team || raise("Team not found!")
    end

    def get_pt_value(target_ml, opposite_ml = 0)
      if opposite_ml.zero?
        target_ml = 10000.0/target_ml if target_ml < 0
        value = (15 * (1 + target_ml.to_d.abs/100) * 0.95)
      else
        total_ml = (target_ml.abs + opposite_ml.abs).to_d/2
        return 15.to_d if total_ml == 0

        prob = if target_ml > opposite_ml
                 100/(100 + total_ml)
               else
                 1-100/(100 + total_ml)
               end

        value = 1/prob * 0.95 * Roster::FB_CHARGE * 10
      end
      value.round
    end

    def get_dayly_wins_pt(target_ml, opposite_ml)
      target_ml = target_ml/100
      opposite_ml = opposite_ml/100
      target_ml = 1.to_f/target_ml.abs if target_ml < 0
      opposite_ml = 1.to_f/opposite_ml.abs if opposite_ml < 0

      0.95*15*(target_ml + opposite_ml+2)/(opposite_ml+1)
    end

    private

    def get_xml(url)
      attempts = 0
      begin
        Nokogiri::XML(open(url))
      rescue
        sleep(1)
        attempts += 1
        retry if attempts <= 5
      end
    end

    def less_then_n_min(node, required_time)
      return unless required_time

      minutes = node.search("statistics").at_xpath("@minutes")
      points = node.search("statistics").at_xpath("@points")

      min_val = minutes.value.split(":")[0..-2].join("") if minutes
      return true unless min_val

      min_val.to_i <= required_time
    end

  end
end
